//
//  OpenRouterCreditManager.swift
//  OpenRouterCreditMenuBar
//

import Foundation
import Combine
import SwiftUI

enum OpenRouterAPIError: Error, LocalizedError {
    case forbidden(String)
    case unauthorized(String)
    case rateLimited(String)
    case httpStatus(Int)
    case invalidResponse
    case noData
    case parsingFailed(Error)
}

enum ConnectionErrorType: String {
    case invalidAPIKey = "Invalid API Key"
    case permissionDenied = "Permission Denied"
    case rateLimited = "Rate Limited"
    case serverError = "Server Error"
    case networkError = "Network Error"
    case invalidResponse = "Invalid Response"
    case unknown = "Unknown Error"
}

extension OpenRouterAPIError {
    var errorDescription: String? {
        switch self {
        case .forbidden: return "Invalid or missing API key for credit tracking"
        case .unauthorized: return "Invalid or expired API key"
        case .rateLimited: return "API rate limit exceeded"
        case .httpStatus(let code): return "HTTP Error: \(code)"
        case .invalidResponse: return "Invalid API response"
        case .noData: return "No data received"
        case .parsingFailed(let error): return "Parsing failed: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .forbidden:
            return "Please verify your API key in Settings"
        case .unauthorized:
            return "Check your API key and try again"
        case .rateLimited:
            return "Wait a few minutes and try again"
        default:
            return nil
        }
    }
}

// Connection Test Result
struct ConnectionTestResult {
    let success: Bool
    let errorType: ConnectionErrorType?
    let errorMessage: String?
}

class OpenRouterCreditManager: ObservableObject {
    @Published var currentCredit: Double?
    @Published var totalUsage: Double?
    @Published var tokensIn: Int?
    @Published var tokensOut: Int?
    @Published var lastUpdated: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var connectionTestStatus: ConnectionTestResult? = nil
    @Published var connectionTestProgress: String? = nil

    private let userDefaults = UserDefaults.standard
    private var refreshTimer: Timer?
    private let cacheKey = "token_usage_cache"

    // MARK: - Connection Testing

    @MainActor func testConnection() async {
        isLoading = true
        connectionTestStatus = nil
        connectionTestProgress = "Testing OpenRouter API server..."

        // Test multiple endpoints in order of preference
        var result: ConnectionTestResult? = await testAuthEndpoint()

        if result == nil {
            connectionTestProgress = "Testing credits endpoint..."
            result = await testCreditsEndpoint()
        }

        if result == nil {
            connectionTestProgress = "Testing models endpoint..."
            result = await testModelsEndpoint()
        }

        isLoading = false
        connectionTestStatus = result

        // Show final success message if all tests passed
        if let result = result, result.success {
            connectionTestProgress = "All tests passed - Connection successful!"
        } else if let result = result, !result.success {
            connectionTestProgress = "Connection failed: " + (result.errorMessage ?? "Unknown error")
        }
    }

    private func testAuthEndpoint() async -> ConnectionTestResult? {
        // Try lightweight auth endpoint first (if it exists)
        guard let url = URL(string: "https://openrouter.ai/api/v1/auth/check") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ConnectionTestResult(success: false, errorType: .invalidResponse, errorMessage: "Invalid server response")
            }

            // For auth endpoint, only return success if it's 200-299
            // If it's 404, return nil to try next endpoint
            if (200...299).contains(httpResponse.statusCode) {
                await MainActor.run {
                    connectionTestProgress = "✓ OpenRouter API server: Connected"
                }
                return ConnectionTestResult(success: true, errorType: nil, errorMessage: "Connection successful")
            } else if httpResponse.statusCode == 404 {
                // Auth endpoint doesn't exist, try next one
                return nil
            } else {
                return mapHTTPStatusToError(httpResponse.statusCode)
            }

        } catch let error as URLError {
            return ConnectionTestResult(success: false, errorType: .networkError, errorMessage: error.localizedDescription)
        } catch {
            return ConnectionTestResult(success: false, errorType: .unknown, errorMessage: error.localizedDescription)
        }
    }

    private func testCreditsEndpoint() async -> ConnectionTestResult? {
        do {
            let creditData = try await fetchCreditFromAPI()
            await MainActor.run {
                connectionTestProgress = "✓ Credits endpoint: Connected"
            }
            return ConnectionTestResult(success: true, errorType: nil, errorMessage: "Connected successfully - Credit balance: $" + String(format: "%.2f", creditData.total_credits - creditData.total_usage))
        } catch let error as OpenRouterAPIError {
            return mapAPIErrorToConnectionError(error)
        } catch {
            return ConnectionTestResult(success: false, errorType: .unknown, errorMessage: error.localizedDescription)
        }
    }

    private func testModelsEndpoint() async -> ConnectionTestResult? {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ConnectionTestResult(success: false, errorType: .invalidResponse, errorMessage: "Invalid server response")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return mapHTTPStatusToError(httpResponse.statusCode)
            }

            // Try to parse as JSON to verify it's a valid models response
            if (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil {
                await MainActor.run {
                    connectionTestProgress = "✓ Models endpoint: Connected"
                }
                return ConnectionTestResult(success: true, errorType: nil, errorMessage: "Connected successfully - Models endpoint working")
            }

            return ConnectionTestResult(success: false, errorType: .invalidResponse, errorMessage: "Invalid response format")

        } catch let error as URLError {
            return ConnectionTestResult(success: false, errorType: .networkError, errorMessage: error.localizedDescription)
        } catch {
            return ConnectionTestResult(success: false, errorType: .unknown, errorMessage: error.localizedDescription)
        }
    }

    private func mapHTTPStatusToError(_ statusCode: Int) -> ConnectionTestResult {
        switch statusCode {
        case 401:
            return ConnectionTestResult(success: false, errorType: .invalidAPIKey, errorMessage: "Invalid or expired API key")
        case 403:
            return ConnectionTestResult(success: false, errorType: .permissionDenied, errorMessage: "API key doesn't have required permissions")
        case 429:
            return ConnectionTestResult(success: false, errorType: .rateLimited, errorMessage: "API rate limit exceeded")
        case 500...599:
            return ConnectionTestResult(success: false, errorType: .serverError, errorMessage: "Server error - OpenRouter API may be down")
        default:
            return ConnectionTestResult(success: false, errorType: .unknown, errorMessage: "HTTP Error: \(statusCode)")
        }
    }

    private func mapAPIErrorToConnectionError(_ error: OpenRouterAPIError) -> ConnectionTestResult {
        switch error {
        case .forbidden:
            return ConnectionTestResult(success: false, errorType: .permissionDenied, errorMessage: "API key doesn't have required permissions")
        case .unauthorized:
            return ConnectionTestResult(success: false, errorType: .invalidAPIKey, errorMessage: "Invalid or expired API key")
        case .rateLimited:
            return ConnectionTestResult(success: false, errorType: .rateLimited, errorMessage: "API rate limit exceeded")
        case .httpStatus(let code):
            return mapHTTPStatusToError(code)
        case .invalidResponse:
            return ConnectionTestResult(success: false, errorType: .invalidResponse, errorMessage: "Invalid API response format")
        case .noData:
            return ConnectionTestResult(success: false, errorType: .invalidResponse, errorMessage: "No data received from server")
        case .parsingFailed:
            return ConnectionTestResult(success: false, errorType: .invalidResponse, errorMessage: "Failed to parse server response")
        }
    }

    private var cachedAPIKey: String? = nil

    var apiKey: String {
        get {
            if let cached = cachedAPIKey {
                return cached
            }
            let key = SimpleSecureStorage.retrieveAPIKeySecurely() ?? ""
            cachedAPIKey = key
            return key
        }
        set {
            // Trim whitespace and newlines
            let cleanKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Clear cache when setting new value
            cachedAPIKey = nil
            if !cleanKey.isEmpty {
                _ = SimpleSecureStorage.storeAPIKeySecurely(cleanKey)
            }
            else {
                SimpleSecureStorage.clearAPIKeySecurely()
            }
        }
    }

    var isEnabled: Bool {
        get {
            userDefaults.bool(forKey: "app_enabled")
        }
        set {
            userDefaults.set(newValue, forKey: "app_enabled")
        }
    }

    var refreshInterval: Double {
        get {
            let interval = userDefaults.double(forKey: "refresh_interval")
            return interval > 0 ? interval : 300  // default 5 minutes
        }
        set {
            userDefaults.set(newValue, forKey: "refresh_interval")
            setupTimer()
        }
    }

    init() {
        // Load latest cached data on initialization from history dump
        if let cache = loadCache(), let latest = cache.history.last {
            self.tokensIn = latest.tokensIn
            self.tokensOut = latest.tokensOut
            self.lastUpdated = latest.date
        }
        setupTimer()
    }

    private func setupTimer() {
        refreshTimer?.invalidate()

        guard isEnabled && !apiKey.isEmpty else { return }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task {
                await self.fetchCredit()
            }
        }
    }

    func startMonitoring() {
        setupTimer()
        Task {
            await fetchCredit()
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Caching
    
    struct TokenUsageEntry: Codable {
        let tokensIn: Int
        let tokensOut: Int
        let date: Date
    }

    struct TokenUsageCache: Codable {
        var history: [TokenUsageEntry] = []
    }

    private func saveToCache(tokensIn: Int, tokensOut: Int, date: Date) {
        var cache = loadCache() ?? TokenUsageCache()
        let newEntry = TokenUsageEntry(tokensIn: tokensIn, tokensOut: tokensOut, date: date)
        
        // Append to history
        cache.history.append(newEntry)
        
        // Keep history manageable (e.g., last 100 entries) if needed, 
        // but user requested a "dump of all past", so I'll keep them for now.
        
        if let encoded = try? JSONEncoder().encode(cache) {
            userDefaults.set(encoded, forKey: cacheKey)
        }
    }

    private func loadCache() -> TokenUsageCache? {
        guard let data = userDefaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(TokenUsageCache.self, from: data)
    }

    func fetchCredit() async {
        guard !apiKey.isEmpty && isEnabled else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Fetch credit primarily
            let creditData = try await fetchCreditFromAPI()
            
            // Attempt to fetch token usage, but don't fail the whole operation if it fails
            var tokenUsage: TokenUsageData? = nil
            do {
                tokenUsage = try await fetchTokenUsageFromAPI()
            } catch {
                print("Token usage fetch failed: \(error.localizedDescription)")
                // We proceed without token usage update, keeping old values or showing partial data
            }

            let now = Date()

            await MainActor.run {
                self.currentCredit = creditData.total_credits - creditData.total_usage
                self.totalUsage = creditData.total_usage
                
                if let usage = tokenUsage {
                    self.tokensIn = usage.tokensIn
                    self.tokensOut = usage.tokensOut
                    
                    // Persist to historical dump in local storage only if we got new data
                    self.saveToCache(tokensIn: usage.tokensIn, tokensOut: usage.tokensOut, date: now)
                }
                
                self.lastUpdated = now
                self.isLoading = false
            }
            
        } catch let error as OpenRouterAPIError {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                if let suggestion = error.recoverySuggestion {
                    self.errorMessage? += "\n" + suggestion
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func fetchCreditFromAPI() async throws -> CreditData {
        guard let url = URL(string: "https://openrouter.ai/api/v1/credits") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 403 {
                throw OpenRouterAPIError.forbidden("API key may not have permission for credits endpoint")
            } else if httpResponse.statusCode == 401 {
                throw OpenRouterAPIError.unauthorized("Invalid or expired API key")
            } else if httpResponse.statusCode == 429 {
                throw OpenRouterAPIError.rateLimited("API rate limit exceeded")
            } else {
                throw OpenRouterAPIError.httpStatus(httpResponse.statusCode)
            }
        }

        let creditResponse = try JSONDecoder().decode(CreditResponse.self, from: data)
        return creditResponse.data
    }

    private func fetchTokenUsageFromAPI() async throws -> TokenUsageData {
        // Try usage endpoint first
        do {
            let usageData = try await fetchTokenUsageFromUsageEndpoint()
            return usageData
        } catch {
            // Fallback to activity endpoint
            let activityData = try await fetchTokenUsageFromActivityEndpoint()
            return activityData
        }
    }

    private func fetchTokenUsageFromUsageEndpoint() async throws -> TokenUsageData {
        guard let url = URL(string: "https://openrouter.ai/api/v1/usage") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 {
                throw OpenRouterAPIError.forbidden("API key may not have permission for token usage endpoints")
            } else if httpResponse.statusCode == 401 {
                throw OpenRouterAPIError.unauthorized("Invalid or expired API key")
            } else if httpResponse.statusCode == 429 {
                throw OpenRouterAPIError.rateLimited("API rate limit exceeded")
            } else {
                throw OpenRouterAPIError.httpStatus(httpResponse.statusCode)
            }
        }

        do {
            let usageResponse = try JSONDecoder().decode(UsageResponse.self, from: data)
            return TokenUsageData(tokensIn: usageResponse.data.tokens_in, tokensOut: usageResponse.data.tokens_out)
        } catch {
            // Try manual extraction
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let dataDict = json["data"] as? [String: Any] {
                let tokensIn = dataDict["tokens_in"] as? Int ?? dataDict["total_tokens_in"] as? Int ?? 0
                let tokensOut = dataDict["tokens_out"] as? Int ?? dataDict["total_tokens_out"] as? Int ?? 0
                return TokenUsageData(tokensIn: tokensIn, tokensOut: tokensOut)
            }
            throw error
        }
    }

    private func fetchTokenUsageFromActivityEndpoint() async throws -> TokenUsageData {
        guard let url = URL(string: "https://openrouter.ai/api/v1/activity") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 {
                throw OpenRouterAPIError.forbidden("API key may not have permission for token usage endpoints")
            } else if httpResponse.statusCode == 401 {
                throw OpenRouterAPIError.unauthorized("Invalid or expired API key")
            } else if httpResponse.statusCode == 429 {
                throw OpenRouterAPIError.rateLimited("API rate limit exceeded")
            } else {
                throw OpenRouterAPIError.httpStatus(httpResponse.statusCode)
            }
        }

        do {
            let activityResponse = try JSONDecoder().decode(ActivityResponse.self, from: data)
            return TokenUsageData(tokensIn: activityResponse.data.total_tokens_in, tokensOut: activityResponse.data.total_tokens_out)
        } catch {
            // Try manual extraction
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let dataDict = json["data"] as? [String: Any] {
                let tokensIn = dataDict["total_tokens_in"] as? Int ?? dataDict["tokens_in"] as? Int ?? 0
                let tokensOut = dataDict["total_tokens_out"] as? Int ?? dataDict["tokens_out"] as? Int ?? 0
                return TokenUsageData(tokensIn: tokensIn, tokensOut: tokensOut)
            }
            throw error
        }
    }
}

// Data models for token usage
struct UsageResponse: Codable {
    let data: UsageData
}

struct UsageData: Codable {
    let tokens_in: Int
    let tokens_out: Int
    let period: String
}

struct ActivityResponse: Codable {
    let data: ActivityData
}

struct ActivityData: Codable {
    let activity: [ActivityItem]
    let total_tokens_in: Int
    let total_tokens_out: Int
}

struct ActivityItem: Codable {
    let id: String
    let model: String
    let tokens_in: Int
    let tokens_out: Int
    let timestamp: String
    let cost: Double
}

struct TokenUsageData {
    let tokensIn: Int
    let tokensOut: Int
}


struct CreditResponse: Codable {
    let data: CreditData
}

struct CreditData: Codable {
    let total_credits: Double
    let total_usage: Double
}
