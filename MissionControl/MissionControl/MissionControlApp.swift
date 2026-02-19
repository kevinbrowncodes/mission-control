//
//  MissionControlApp.swift
//  MissionControl
//
//  Created by Kevin Brown on 2/19/26.
//

import SwiftUI
import AppKit
import ServiceManagement

@main
struct MissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows — app runs from the menu bar
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.3.group",
                                   accessibilityDescription: "Mission Control")
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            openMissionControl()
        }
    }

    func openMissionControl() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Mission Control.app")
        NSWorkspace.shared.open(url)
    }

    func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Mission Control", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        // Temporarily assign menu, trigger it, then clear so left-click stays unaffected
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @State private var openAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Open at Login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("Failed to update login item: \(error)")
                    }
                }
        }
        .formStyle(.grouped)
        .frame(width: 320, height: 120)
        .padding()
    }
}
