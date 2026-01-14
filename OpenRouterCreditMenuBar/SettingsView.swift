//
//  SettingsView.swift
//  OpenRouterCreditMenuBar
//

import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var creditManager: OpenRouterCreditManager
    @State private var apiKey: String = ""
    @State private var isEnabled: Bool = true
    @State private var openAtLogin: Bool = false
    @State private var refreshInterval: Double = 300  // default 5 minutes
    
    // Multi-key support
    @State private var useMultipleKeys: Bool = false
    @State private var newKeyName: String = ""
    @State private var newKeyString: String = ""

    private let refreshIntervalOptions: [Double] = [30, 60, 180, 300, 600, 1800, 3600]

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable Credit Monitoring", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        creditManager.isEnabled = newValue
                        if newValue {
                            Task {
                                await creditManager.fetchCredit()
                            }
                        }
                    }

                Toggle("Open at Login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in
                        setLoginItemEnabled(newValue)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Refresh Interval")
                        Spacer()
                        Picker("", selection: $refreshInterval) {
                            Text("30 seconds").tag(30.0)
                            Text("1 minute").tag(60.0)
                            Text("3 minutes").tag(180.0)
                            Text("5 minutes").tag(300.0)
                            Text("10 minutes").tag(600.0)
                            Text("30 minutes").tag(1800.0)
                            Text("1 hour").tag(3600.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .onChange(of: refreshInterval) { _, newValue in
                            creditManager.refreshInterval = newValue
                        }
                    }
                    
                    Text("How often to check credit balance")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("API Configuration") {
                Picker("Key Mode", selection: $useMultipleKeys) {
                    Text("Single Key").tag(false)
                    Text("Multiple Keys").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: useMultipleKeys) { _, newValue in
                    creditManager.useMultipleKeys = newValue
                }
                .padding(.bottom, 4)

                if useMultipleKeys {
                    // Header Row
                    HStack {
                        Text("Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)
                        Text("Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    
                    List {
                        ForEach(creditManager.apiKeyEntries) { entry in
                            HStack {
                                Text(entry.name)
                                    .frame(width: 100, alignment: .leading)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                Text(maskKey(entry.key))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                // Status Indicator
                                if let status = creditManager.apiKeyStatuses.first(where: { $0.id == entry.id }) {
                                    if status.error != nil {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                            .help(status.error!)
                                            .padding(.leading, 4)
                                    } else if status.usage != nil {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .padding(.leading, 4)
                                    }
                                }
                                
                                Button(action: {
                                    removeKey(entry)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                                .padding(.leading, 4)
                                
                                Spacer()
                            }
                        }
                    }
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack {
                            Text("Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            TextField("", text: $newKeyName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }
                        
                        HStack {
                            Text("API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            SecureField("", text: $newKeyString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }
                        
                        Button("Add") {
                            addKey()
                        }
                        .disabled(newKeyString.isEmpty || newKeyName.isEmpty)
                        .padding(.top, 4)
                    }
                    .padding(.top, 8)
                    
                    if !creditManager.apiKeyEntries.isEmpty {
                        Text("\(creditManager.apiKeyEntries.count) keys configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    
                } else {
                    SecureField("OpenRouter API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, newValue in
                            creditManager.apiKey = newValue
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Test Connection") {
                            Task {
                                await creditManager.testConnection()
                            }
                        }
                        .disabled((useMultipleKeys && creditManager.apiKeyEntries.isEmpty) || (!useMultipleKeys && apiKey.isEmpty))

                        if creditManager.isLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                        }

                        // Show connection test result
                        if let testResult = creditManager.connectionTestStatus {
                            if testResult.success {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else if testResult.errorType == .partialFailure {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    // Show detailed test progress
                    if let progress = creditManager.connectionTestProgress {
                        HStack {
                            if creditManager.isLoading {
                                ProgressView()
                                    .scaleEffect(0.4)
                            }
                            Text(progress)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Show detailed test result message
                if let testResult = creditManager.connectionTestStatus {
                    HStack {
                        if testResult.success {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(testResult.errorMessage ?? "Connection successful")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else if testResult.errorType == .partialFailure {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(testResult.errorMessage ?? "Partial failure")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(testResult.errorMessage ?? "Connection failed")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            if let error = creditManager.errorMessage {
                Section("Status") {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 400, maxHeight: .infinity)
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        apiKey = creditManager.apiKey
        isEnabled = creditManager.isEnabled
        refreshInterval = creditManager.refreshInterval
        useMultipleKeys = creditManager.useMultipleKeys
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
    
    private func addKey() {
        let trimmedKey = newKeyString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = newKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmedKey.isEmpty && !trimmedName.isEmpty {
            var currentEntries = creditManager.apiKeyEntries
            // Allow duplicate names? Yes. Allow duplicate keys? No.
            if !currentEntries.contains(where: { $0.key == trimmedKey }) {
                let newEntry = APIKeyEntry(key: trimmedKey, name: trimmedName)
                currentEntries.append(newEntry)
                creditManager.apiKeyEntries = currentEntries
                newKeyString = ""
                newKeyName = ""
                
                // Trigger fetch to validate/update
                Task {
                    await creditManager.fetchCredit()
                }
            }
        }
    }
    
    private func removeKey(_ entry: APIKeyEntry) {
        var currentEntries = creditManager.apiKeyEntries
        currentEntries.removeAll { $0.id == entry.id }
        creditManager.apiKeyEntries = currentEntries
        
        Task {
            await creditManager.fetchCredit()
        }
    }
    
    private func maskKey(_ key: String) -> String {
        if key.count <= 3 { return "***" }
        let suffix = key.suffix(3)
        return "...\(suffix)"
    }

    private func setLoginItemEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") login item: \(error)")
        }
    }
}