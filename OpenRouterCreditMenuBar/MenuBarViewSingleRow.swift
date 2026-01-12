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
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "creditcard")
                    .foregroundColor(.blue)
                Text("OpenRouter Credit")
                    .font(.headline)
            }
            .padding(.top, 8)

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
                    // Credit Amount
                    Text(String(format: "$%.4f", credit))
                        .font(.system(size: 12))
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                    
                    // Token Usage Stats
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
                    }
                    
                    if let lastUpdated = creditManager.lastUpdated {
                        Text("Updated \(getRelativeTime(for: lastUpdated))")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.top, 1)
                    }
                }
                .padding(.vertical, 4)
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
            } else if creditManager.apiKey.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "key.fill")
                        .foregroundColor(.blue)
                    Text("API Key Required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Please set your OpenRouter API key in Settings to track your credit balance.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            }

            Divider()

            VStack(spacing: 8) {
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
        .padding()
        .frame(width: 200)
    }
}