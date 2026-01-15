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
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if let credit = creditManager.currentCredit {
                Text("$\(String(format: "%.2f", credit))")
                    .font(.system(size: 11, weight: .medium)) // Slightly larger for readability
            } else {
                Text("...")
                    .font(.system(size: 11, weight: .regular))
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
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
        // Close popover first to ensure clean state
        if popover?.isShown == true {
            popover?.performClose(nil)
        }

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
            
            // Handle window closing
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: settingsWindow,
                queue: .main
            ) { [weak self] _ in
                // Only revert if we are not keeping it open for some other reason (simple logic here)
                NSApp.setActivationPolicy(originalPolicy)
                self?.settingsWindow = nil
            }
        }
        
        // Ensure activation happens after current runloop cycle to allow policy change to take effect
        DispatchQueue.main.async {
            self.settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
