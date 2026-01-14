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
    case partialFailure = "Partial Failure"
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

struct APIKeyEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    let key: String
    let name: String
}

struct APIKeyStatus: Identifiable {
    var id: UUID { entry.id }
    let entry: APIKeyEntry
    var usage: Double?
    var limit: Double?
    var error: String?
}

class OpenRouterCreditManager: ObservableObject {
    @Published var currentCredit: Double?
    @Published var totalUsage: Double?
    @Published var usageCost: Double?
    @Published var limitCost: Double?
    @Published var tokensIn: Int?
    @Published var tokensOut: Int?
    
    // Multi-key support
    @Published var apiKeyStatuses: [APIKeyStatus] = []
    
    // Cumulative Stats
    @Published var cumulativeTokensIn: Int = 0
    @Published var cumulativeTokensOut: Int = 0
    @Published var cumulativeUsageCost: Double = 0.0
    
    @Published var lastUpdated: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var connectionTestStatus: ConnectionTestResult? = nil
    @Published var connectionTestProgress: String? = nil

    private let userDefaults = UserDefaults.standard
    private var refreshTimer: Timer?
    private let cacheKey = "token_usage_cache"
    private let storageManager = FileStorageManager()

    // MARK: - Connection Testing

    @MainActor func testConnection() async {
        if useMultipleKeys {
            if let firstEntry = apiKeyEntries.first {
                isLoading = true
                connectionTestStatus = nil
                connectionTestProgress = "Testing OpenRouter API server..."
                
                // 1. Test Server Connectivity (Once)
                // Try auth endpoint, fallback to credits endpoint if needed
                var connectivityResult = await testAuthEndpoint(key: firstEntry.key)
                if connectivityResult == nil {
                     connectivityResult = await testCreditsEndpoint(key: firstEntry.key)
                }
                
                if let result = connectivityResult, result.success {
                    connectionTestProgress = "Verifying keys..."
                    // 2. Perform credit check for all keys (Once) via fetchCredit logic
                    await fetchCredit()
                    
                    // Check results
                    let failedKeys = apiKeyStatuses.filter { $0.error != nil }
                    if failedKeys.isEmpty {
                        connectionTestStatus = ConnectionTestResult(success: true, errorType: nil, errorMessage: "All keys verified successfully")
                        connectionTestProgress = "All tests passed - Connection successful!"
                    } else {
                        connectionTestStatus = ConnectionTestResult(success: false, errorType: .partialFailure, errorMessage: "\(failedKeys.count) key(s) failed validation")
                        connectionTestProgress = "Connection verified, but some keys failed."
                    }
                    isLoading = false
                } else {
                    isLoading = false
                    connectionTestStatus = connectivityResult
                    connectionTestProgress = "Server connection failed."
                }
            } else {
                 isLoading = false
                 connectionTestStatus = ConnectionTestResult(success: false, errorType: .invalidAPIKey, errorMessage: "No API keys configured")
            }
        } else {
            await testConnection(key: apiKey)
        }
    }

    @MainActor func testConnection(key: String) async {
        isLoading = true
        connectionTestStatus = nil
        connectionTestProgress = "Testing OpenRouter API server..."

        // Test multiple endpoints in order of preference
        var result: ConnectionTestResult? = await testAuthEndpoint(key: key)

        if result == nil {
            connectionTestProgress = "Testing credits endpoint..."
            result = await testCreditsEndpoint(key: key)
        }

        if result == nil {
            connectionTestProgress = "Testing models endpoint..."
            result = await testModelsEndpoint(key: key)
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


    private func testAuthEndpoint(key: String) async -> ConnectionTestResult? {
        // Try lightweight auth endpoint first (if it exists)
        guard let url = URL(string: "https://openrouter.ai/api/v1/auth/check") else { 
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

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

    private func testCreditsEndpoint(key: String) async -> ConnectionTestResult? {
        do {
            let creditData = try await fetchCreditFromAPI(key: key)
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

    private func testModelsEndpoint(key: String) async -> ConnectionTestResult? {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { 
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

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
    private var cachedAPIKeyEntries: [APIKeyEntry]? = nil

    var useMultipleKeys: Bool {
        get {
            userDefaults.bool(forKey: "use_multiple_keys")
        }
        set {
            userDefaults.set(newValue, forKey: "use_multiple_keys")
            // Clear caches to force reload if needed
            cachedAPIKey = nil
            cachedAPIKeyEntries = nil
            
            Task {
                 await fetchCredit()
            }
        }
    }

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
    
    var apiKeyEntries: [APIKeyEntry] {
        get {
            if let cached = cachedAPIKeyEntries {
                return cached
            }
            let entries = SimpleSecureStorage.retrieveAPIKeyEntriesSecurely()
            cachedAPIKeyEntries = entries
            return entries
        }
        set {
            cachedAPIKeyEntries = nil
            _ = SimpleSecureStorage.storeAPIKeyEntriesSecurely(newValue)
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
        // Load cached history on initialization
        let history = storageManager.loadHistory()
        updateCumulativeStats(history: history)
        
        // Also try to load the latest snapshot for display
        if let latest = history.first { // History is sorted desc
            self.tokensIn = latest.tokensIn
            self.tokensOut = latest.tokensOut
            self.usageCost = latest.usageCost
            self.lastUpdated = latest.date
        }
        setupTimer()
    }
    
    private func updateCumulativeStats(history: [TokenUsageEntry]) {
        self.cumulativeTokensIn = history.reduce(0) { $0 + ($1.tokensIn ?? 0) }
        self.cumulativeTokensOut = history.reduce(0) { $0 + ($1.tokensOut ?? 0) }
        self.cumulativeUsageCost = history.reduce(0.0) { $0 + ($1.usageCost ?? 0.0) }
    }

    private func setupTimer() {
        refreshTimer?.invalidate()

        let hasKey = useMultipleKeys ? !apiKeyEntries.isEmpty : !apiKey.isEmpty
        guard isEnabled && hasKey else { return }

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

    func fetchCredit() async {
        let hasKey = useMultipleKeys ? !apiKeyEntries.isEmpty : !apiKey.isEmpty
        guard hasKey && isEnabled else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let primaryKey = useMultipleKeys ? apiKeyEntries.first!.key : apiKey
            
            async let creditTask = fetchCreditFromAPI(key: primaryKey)
            
            // Trigger full history fetch in background
            Task {
                await self.fetchAndCacheAllActivity(key: primaryKey)
            }
            
            // Also attempt token usage (legacy/provisioning keys)
            let tokenUsageTask = Task { () -> TokenUsageData? in
                try? await self.fetchTokenUsageFromAPI(key: primaryKey)
            }

            if useMultipleKeys {
                var newStatuses: [APIKeyStatus] = []
                
                await withTaskGroup(of: APIKeyStatus.self) { group in
                    for entry in apiKeyEntries {
                        group.addTask {
                            do {
                                let details = try await self.fetchKeyDetailsFromAPI(key: entry.key)
                                // Use local name if available, otherwise fallback (though local name is mandatory now)
                                return APIKeyStatus(entry: entry, usage: details.usage, limit: details.limit, error: nil)
                            } catch {
                                return APIKeyStatus(entry: entry, usage: nil, limit: nil, error: error.localizedDescription)
                            }
                        }
                    }
                    
                    for await status in group {
                        newStatuses.append(status)
                    }
                }
                
                // Restore order
                let orderedStatuses = apiKeyEntries.compactMap { entry in
                    newStatuses.first(where: { $0.entry.id == entry.id })
                }
                
                let creditData = try await creditTask
                let tokenUsage = await tokenUsageTask.value
                let now = Date()
                
                await MainActor.run {
                    self.currentCredit = creditData.total_credits - creditData.total_usage
                    self.totalUsage = creditData.total_usage
                    self.apiKeyStatuses = orderedStatuses
                    
                    if let usage = tokenUsage {
                        self.tokensIn = usage.tokensIn
                        self.tokensOut = usage.tokensOut
                    }
                    
                    self.lastUpdated = now
                    self.isLoading = false
                    
                    // For history, sum up usage from keys
                    let totalKeyUsage = orderedStatuses.reduce(0.0) { $0 + ($1.usage ?? 0.0) }
                    
                    let newEntry = TokenUsageEntry(
                        id: UUID().uuidString,
                        tokensIn: tokenUsage?.tokensIn,
                        tokensOut: tokenUsage?.tokensOut,
                        usageCost: totalKeyUsage,
                        date: now
                    )
                    self.storageManager.appendEntry(newEntry)
                    
                    let history = self.storageManager.loadHistory()
                    self.updateCumulativeStats(history: history)
                }
                
            } else {
                async let keyDetailsTask = fetchKeyDetailsFromAPI(key: apiKey)
                let (creditData, keyDetails) = try await (creditTask, keyDetailsTask)
                let tokenUsage = await tokenUsageTask.value
                
                let now = Date()

                await MainActor.run {
                    self.currentCredit = creditData.total_credits - creditData.total_usage
                    self.totalUsage = creditData.total_usage
                    self.usageCost = keyDetails.usage
                    self.limitCost = keyDetails.limit
                    
                    if let usage = tokenUsage {
                        self.tokensIn = usage.tokensIn
                        self.tokensOut = usage.tokensOut
                    }
                    
                    self.lastUpdated = now
                    self.isLoading = false
                    
                    // Save to historical file
                    let newEntry = TokenUsageEntry(
                        id: UUID().uuidString,
                        tokensIn: tokenUsage?.tokensIn,
                        tokensOut: tokenUsage?.tokensOut,
                        usageCost: keyDetails.usage,
                        date: now
                    )
                    self.storageManager.appendEntry(newEntry)
                    
                    // Update cumulative stats from the full history
                    let history = self.storageManager.loadHistory()
                    self.updateCumulativeStats(history: history)
                }
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

    private func fetchAndCacheAllActivity(key: String? = nil) async {
        let apiKey = key ?? self.apiKey
        guard !apiKey.isEmpty, let url = URL(string: "https://openrouter.ai/api/v1/activity") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }
            
            let activityResponse = try JSONDecoder().decode(ActivityResponse.self, from: data)
            let items = activityResponse.data.activity
            
            let entries = items.map {
                TokenUsageEntry(
                    id: $0.id ?? UUID().uuidString,
                    tokensIn: $0.effectiveTokensIn,
                    tokensOut: $0.effectiveTokensOut,
                    usageCost: $0.cost,
                    date: ISO8601DateFormatter().date(from: $0.timestamp ?? "") ?? Date()
                )
            }
            
            self.storageManager.mergeHistory(entries)
            
            let history = self.storageManager.loadHistory()
            await MainActor.run {
                self.updateCumulativeStats(history: history)
            }
        } catch {
            print("Failed to fetch activity history: \(error)")
        }
    }

    private func fetchKeyDetailsFromAPI(key: String? = nil) async throws -> KeyAuthData {
        let apiKey = key ?? self.apiKey
        guard let url = URL(string: "https://openrouter.ai/api/v1/auth/key") else { 
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
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("Auth/Key API Error \(httpResponse.statusCode): \(body)")
            throw OpenRouterAPIError.httpStatus(httpResponse.statusCode)
        }

        let keyResponse = try JSONDecoder().decode(KeyAuthResponse.self, from: data)
        return keyResponse.data
    }

    private func fetchCreditFromAPI(key: String? = nil) async throws -> CreditData {
        let apiKey = key ?? self.apiKey
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

    private func fetchTokenUsageFromAPI(key: String? = nil) async throws -> TokenUsageData {
        let apiKey = key ?? self.apiKey
        do {
            let usageData = try await fetchTokenUsageFromUsageEndpoint(key: apiKey)
            return usageData
        } catch {
            let activityData = try await fetchTokenUsageFromActivityEndpoint(key: apiKey)
            return activityData
        }
    }

    private func fetchTokenUsageFromUsageEndpoint(key: String) async throws -> TokenUsageData {
        guard let url = URL(string: "https://openrouter.ai/api/v1/usage") else { 
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterAPIError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            let logMsg = "Usage API Error \(httpResponse.statusCode): \(body)\n"
            if let logData = logMsg.data(using: .utf8) {
                let fileURL = URL(fileURLWithPath: "/tmp/openrouter_debug.log")
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(logData)
                    handle.closeFile()
                }
            }
            
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
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let dataDict = json["data"] as? [String: Any] {
                let tokensIn = dataDict["tokens_in"] as? Int ?? dataDict["total_tokens_in"] as? Int ?? 0
                let tokensOut = dataDict["tokens_out"] as? Int ?? dataDict["total_tokens_out"] as? Int ?? 0
                return TokenUsageData(tokensIn: tokensIn, tokensOut: tokensOut)
            }
            throw error
        }
    }

    private func fetchTokenUsageFromActivityEndpoint(key: String) async throws -> TokenUsageData {
        guard let url = URL(string: "https://openrouter.ai/api/v1/activity") else { 
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterAPIError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            let logMsg = "Activity API Error \(httpResponse.statusCode): \(body)\n"
            if let logData = logMsg.data(using: .utf8) {
                let fileURL = URL(fileURLWithPath: "/tmp/openrouter_debug.log")
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(logData)
                    handle.closeFile()
                }
            }

            if httpResponse.statusCode == 403 {
                throw OpenRouterAPIError.forbidden("API key may not have permission for activity endpoint")
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
            
            let totalIn = activityResponse.data.total_tokens_in ?? 0
            let totalOut = activityResponse.data.total_tokens_out ?? 0

            if totalIn == 0 && totalOut == 0 {
                let sumIn = activityResponse.data.activity.reduce(0) { $0 + $1.effectiveTokensIn }
                let sumOut = activityResponse.data.activity.reduce(0) { $0 + $1.effectiveTokensOut }
                return TokenUsageData(tokensIn: sumIn, tokensOut: sumOut)
            }
            
            return TokenUsageData(tokensIn: totalIn, tokensOut: totalOut)
        } catch {
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let dataDict = json["data"] as? [String: Any] {
                
                let tokensIn = dataDict["total_tokens_in"] as? Int ?? dataDict["tokens_in"] as? Int
                let tokensOut = dataDict["total_tokens_out"] as? Int ?? dataDict["tokens_out"] as? Int
                
                if let tIn = tokensIn, let tOut = tokensOut, (tIn > 0 || tOut > 0) {
                    return TokenUsageData(tokensIn: tIn, tokensOut: tOut)
                }
                
                if let activityArray = dataDict["activity"] as? [[String: Any]] {
                    let sumIn = activityArray.reduce(0) { 
                        $0 + ($1["tokens_in"] as? Int ?? $1["prompt_tokens"] as? Int ?? 0) 
                    }
                    let sumOut = activityArray.reduce(0) { 
                        $0 + ($1["tokens_out"] as? Int ?? $1["completion_tokens"] as? Int ?? 0) 
                    }
                    return TokenUsageData(tokensIn: sumIn, tokensOut: sumOut)
                }
            }
            throw error
        }
    }
}

// Data models
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
    let total_tokens_in: Int?
    let total_tokens_out: Int?
}

struct ActivityItem: Codable {
    let id: String?
    let model: String?
    let tokens_in: Int?
    let tokens_out: Int?
    let prompt_tokens: Int?
    let completion_tokens: Int?
    let timestamp: String?
    let cost: Double?
    
    var effectiveTokensIn: Int {
        return tokens_in ?? prompt_tokens ?? 0
    }
    
    var effectiveTokensOut: Int {
        return tokens_out ?? completion_tokens ?? 0
    }
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

struct KeyAuthResponse: Codable {
    let data: KeyAuthData
}

struct KeyAuthData: Codable {
    let label: String?
    let name: String?
    let usage: Double
    let limit: Double?
    let limit_remaining: Double?
}

// File Storage
struct TokenUsageEntry: Codable, Identifiable {
    let id: String
    let tokensIn: Int?
    let tokensOut: Int?
    let usageCost: Double?
    let date: Date
}

class FileStorageManager {
    private let fileName = "usage_history.json"
    
    private var fileURL: URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        if !FileManager.default.fileExists(atPath: documentsDirectory.path) {
            try? FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        }
        return documentsDirectory.appendingPathComponent(fileName)
    }
    
    func appendEntry(_ entry: TokenUsageEntry) {
        var history = loadHistory()
        history.append(entry)
        saveHistory(history)
    }
    
    func mergeHistory(_ newEntries: [TokenUsageEntry]) {
        var history = loadHistory()
        var existingIds = Set(history.map { $0.id })
        
        for entry in newEntries {
            if !existingIds.contains(entry.id) {
                history.append(entry)
                existingIds.insert(entry.id)
            }
        }
        
        history.sort { $0.date > $1.date }
        saveHistory(history)
    }
    
    func saveHistory(_ history: [TokenUsageEntry]) {
        guard let url = fileURL else { return }
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: url)
        }
    }
    
    func loadHistory() -> [TokenUsageEntry] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode([TokenUsageEntry].self, from: data) else { 
            return []
        }
        return history
    }
}