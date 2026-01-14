//
//  OpenRouterCreditMenuBarApp.swift
//  OpenRouterCreditMenuBar
//
//  Created by Kittithat Patepakorn on 24/5/2568 BE.
//

import SwiftUI

@main
struct OpenRouterCreditMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.creditManager)
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}

struct MenuBarDisplayView: View {
    @ObservedObject var creditManager: OpenRouterCreditManager
    
    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        } else {
            return "\(tokens)"
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if let credit = creditManager.currentCredit {
                // Row 1: Credit
                Text("$\(String(format: "%.2f", credit))")
                    .font(.system(size: 10, weight: .regular))
                    .frame(height: 11, alignment: .bottom)
                
                // Row 2: Tokens
                if let tokensIn = creditManager.tokensIn, let tokensOut = creditManager.tokensOut {
                    Text("\(formatTokens(tokensIn))/\(formatTokens(tokensOut))")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(.secondary)
                        .frame(height: 9, alignment: .top)
                } else {
                    // Placeholder to maintain 2-row layout height if tokens not yet loaded
                    Text("- / -")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(.secondary)
                        .frame(height: 9, alignment: .top)
                }
            } else {
                Text("Loading...")
                    .font(.system(size: 10, weight: .regular))
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 22) // Explicitly match menu bar height
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    @Published var creditManager = OpenRouterCreditManager()
    var hostingView: NSHostingView<MenuBarDisplayView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let mainWindow = NSApp.windows.first(where: { $0.title.isEmpty }) {
            mainWindow.close()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let statusButton = statusItem?.button {
            // clear default title
            statusButton.title = ""
            
            let view = MenuBarDisplayView(creditManager: creditManager)
            hostingView = NSHostingView(rootView: view)
            
            if let hostingView = hostingView {
                // Important: Set frame to ensure visibility immediately
                hostingView.frame = NSRect(x: 0, y: 0, width: 100, height: 22)
                hostingView.autoresizingMask = [.width, .height]
                statusButton.addSubview(hostingView)
                
                // Add constraints to ensure it expands the button
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    hostingView.topAnchor.constraint(equalTo: statusButton.topAnchor),
                    hostingView.bottomAnchor.constraint(equalTo: statusButton.bottomAnchor),
                    hostingView.leadingAnchor.constraint(equalTo: statusButton.leadingAnchor),
                    hostingView.trailingAnchor.constraint(equalTo: statusButton.trailingAnchor),
                    // Set a width that fits our text comfortably
                    hostingView.widthAnchor.constraint(equalToConstant: 80)
                ])
            }
            
            statusButton.action = #selector(showMenu)
            statusButton.target = self
        }

        popover = NSPopover()
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarViewSingleRow()
                .environmentObject(creditManager)
        )
        popover?.behavior = .transient

        creditManager.startMonitoring()
    }

    @objc func showSettingsWindow() {
        let originalPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(creditManager)
                .frame(minWidth: 400, minHeight: 450)

            let hostingController = NSHostingController(rootView: settingsView)
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Settings"
            settingsWindow?.setContentSize(NSSize(width: 400, height: 450))
            settingsWindow?.center()
            settingsWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
            settingsWindow?.level = .floating
            settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: settingsWindow,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(originalPolicy)
            self?.settingsWindow = nil
        }
    }

    @objc func showMenu() {
        if let statusButton = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                popover?.show(
                    relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
            }
        }
    }
}
