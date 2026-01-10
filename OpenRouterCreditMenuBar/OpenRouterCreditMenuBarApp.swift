//
//  OpenRouterCreditMenuBarApp.swift
//  OpenRouterCreditMenuBar
//
//  Created by Kittithat Patepakorn on 24/5/2568 BE.
//

import SwiftUI

@main
struct OpenRouterCreditMenuBarApp: App {
    // Use the AppDelegate for menu bar functionality
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar apps should not have automatic windows
        // Settings window will be shown programmatically when needed
        Settings {
            SettingsView()
                .environmentObject(appDelegate.creditManager)
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    @Published var creditManager = OpenRouterCreditManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ซ่อน dock icon แต่ยังคงให้ app สามารถแสดง window ได้
        NSApp.setActivationPolicy(.accessory)

        // ปิดเฉพาะ main window ไม่ใช่ทุก window
        if let mainWindow = NSApp.windows.first(where: { $0.title.isEmpty }) {
            mainWindow.close()
        }

        // สร้าง menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let statusButton = statusItem?.button {
            statusButton.title = "Loading..."
            statusButton.action = #selector(showMenu)
            statusButton.target = self
        }

        // สร้าง popover
        popover = NSPopover()
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarViewSingleRow()
                .environmentObject(creditManager)
        )
        popover?.behavior = .transient

        // Start monitoring (this sets up the timer and does initial fetch)
        creditManager.startMonitoring()

        // Set up timer to update menu bar title when credit changes
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            self.updateMenuBarTitle()
        }
    }

    @objc func showSettingsWindow() {
        // Temporarily change activation policy to regular for proper window focus
        let originalPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        if settingsWindow == nil {
            // Create Settings window programmatically
            let settingsView = SettingsView()
                .environmentObject(creditManager)
                .frame(minWidth: 400, minHeight: 450)  // Taller window

            let hostingController = NSHostingController(rootView: settingsView)
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Settings"
            settingsWindow?.setContentSize(NSSize(width: 400, height: 450))  // Taller window
            settingsWindow?.center()

            // Set window behavior for proper focus
            settingsWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
            settingsWindow?.level = .floating

            // Make key and order front with proper activation
            settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Bring existing window to front
            settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        // Restore original activation policy when window closes
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

    func updateMenuBarTitle() {
        if let credit = creditManager.currentCredit {
            statusItem?.button?.title = "$\(String(format: "%.2f", credit))"
        } else {
            statusItem?.button?.title = "Error"
        }
    }
}
