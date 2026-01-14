//
//  MenuBarViewSingleRow.swift
//  OpenRouterCreditMenuBar
//
//  Single row menu bar view with adjusted padding and font size
//

import SwiftUI

struct MenuBarViewSingleRow: View {
    @EnvironmentObject var creditManager: OpenRouterCreditManager

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        } else {
            return "\(tokens)"
        }
    }
    
    private func getRelativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "creditcard")
                    .foregroundColor(.blue)
                Text("OpenRouter Credit")
                    .font(.headline)
            }
            .padding(.top, 2)

            Divider()

            if creditManager.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading...")
                        .font(.caption)
                }
            } else if let credit = creditManager.currentCredit {
                VStack(spacing: 4) {
                    // Credit Amount (Total Account Credit)
                    Text(String(format: "$%.4f", credit))
                        .font(.system(size: 12))
                        .fontWeight(.regular)
                        .frame(maxWidth: .infinity)
                    
                    if creditManager.useMultipleKeys {
                        // Multi-Key View
                        VStack(spacing: 2) {
                            ForEach(creditManager.apiKeyStatuses) { status in
                                HStack {
                                    Text(status.entry.name)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    if let usage = status.usage {
                                        if let limit = status.limit {
                                            Text("$\(String(format: "%.4f", usage)) / $\(String(format: "%.2f", limit))")
                                        } else {
                                            Text("$\(String(format: "%.4f", usage))")
                                        }
                                    } else {
                                        Text("-")
                                    }
                                }
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                        
                    } else {
                        // Single Key View
                        if let usage = creditManager.usageCost {
                            if let limit = creditManager.limitCost {
                                Text("Used: $\(String(format: "%.4f", usage)) / $\(String(format: "%.2f", limit))")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Used: $\(String(format: "%.4f", usage))")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Token Usage Stats (Global)
                    if let tokensIn = creditManager.tokensIn, let tokensOut = creditManager.tokensOut {
                        HStack(spacing: 12) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 8))
                                Text(formatTokens(tokensIn))
                            }
                            
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 8))
                                Text(formatTokens(tokensOut))
                            }
                        }
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                    }
                    
                    if let lastUpdated = creditManager.lastUpdated {
                        Text("Updated \(getRelativeTime(for: lastUpdated))")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.top, 1)
                    }
                }
                .padding(.vertical, 2)
            } else if let error = creditManager.errorMessage {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Credit Tracking Error")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            } else if (creditManager.useMultipleKeys ? creditManager.apiKeyEntries.isEmpty : creditManager.apiKey.isEmpty) {
                VStack(spacing: 4) {
                    Image(systemName: "key.fill")
                        .foregroundColor(.blue)
                    Text("API Key Required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Please configure your OpenRouter API key(s) in Settings.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            }

            Divider()

            VStack(spacing: 4) {
                Button("Refresh") {
                    Task {
                        await creditManager.fetchCredit()
                    }
                }
                .controlSize(.small)

                Button("View Activity") {
                    if let url = URL(string: "https://openrouter.ai/activity") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)

                Button("Settings") {
                    NSApp.sendAction(#selector(AppDelegate.showSettingsWindow), to: nil, from: nil)
                }
                .controlSize(.small)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(width: 220) // Slightly wider for key names
    }
}
