//
//  MenuBarViewSingleRow.swift
//  OpenRouterCreditMenuBar
//
//  Single row menu bar view with adjusted padding and font size
//

import SwiftUI

struct MenuBarViewSingleRow: View {
    @EnvironmentObject var creditManager: OpenRouterCreditManager

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
                // Single row design with larger font (10pt), no bold
                Text(String(format: "$%.4f", credit))
                    .font(.system(size: 10))
                    .fontWeight(.regular)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
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