//
//  MissionControlApp.swift
//  MissionControl
//
//  Created by Kevin Brown on 2/19/26.
//

import SwiftUI
import AppKit
import Carbon.HIToolbox
import CoreGraphics

// MARK: - App Entry Point

@main
struct MissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var globalEventMonitor: Any?
    private var hotKey: GlobalHotKey?
    private let spaceLabels = SpaceLabelManager()

    /// The app that was in front when the panel opened. Actions that depend on the active
    /// app (App Exposé) hand activation back to it first.
    private var lastFrontmostApp: NSRunningApplication?

    /// A transient popover is dismissed on the mouse-down of a click on the status item.
    /// Remember when that happened so the mouse-up of the same click doesn't reopen it.
    private var popoverClosedAt: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        Preferences.registerDefaults()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.3.group",
                                   accessibilityDescription: "Mission Control Launcher")
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        self.popover = popover

        // Clicks in other apps dismiss the popover even if it never got key focus.
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }

        syncHotKey()
        spaceLabels.start()
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Hot Key

    @objc private func preferencesChanged() {
        syncHotKey()
        spaceLabels.refreshEnabled()
    }

    /// Registers or drops the ⌃⌥M shortcut to match the preference.
    private func syncHotKey() {
        let enabled = UserDefaults.standard.bool(forKey: Preferences.hotKeyEnabledKey)
        if enabled, hotKey == nil {
            hotKey = GlobalHotKey(keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey) { [weak self] in
                self?.togglePopover()
            }
        } else if !enabled {
            hotKey = nil
        }
    }

    // MARK: - Click Handling

    @objc func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let popover else { return }
        if popover.isShown {
            closePopover()
        } else if Date().timeIntervalSince(popoverClosedAt) > 0.3 {
            // If this very click is what just dismissed the popover, leave it closed.
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        // Remember who was in front before we take focus, so the panel can mark it and
        // App Exposé can target it.
        lastFrontmostApp = NSWorkspace.shared.frontmostApplication
        // Fresh content each time so the running-apps list is current.
        popover.contentViewController = NSHostingController(
            rootView: MainPopoverView(
                actions: self, frontmostApp: lastFrontmostApp,
                spaceName: spaceLabels.activeSpaceName,
                spaceNamesEnabled: UserDefaults.standard.bool(forKey: Preferences.spaceLabelsEnabledKey))
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        activateSelf()
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        popoverClosedAt = Date()
    }

    /// Brings this app forward so the popover gets keyboard focus and closes when the
    /// user switches away. `activate(ignoringOtherApps:)` is deprecated from macOS 14.
    private func activateSelf() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Hands activation from this app to another one (cooperative activation on macOS 14+).
    private func activate(_ app: NSRunningApplication, allWindows: Bool) {
        if app.isHidden {
            app.unhide()
        }
        let options: NSApplication.ActivationOptions = allWindows ? [.activateAllWindows] : []
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
            app.activate(options: options)
        } else {
            app.activate(options: options.union(.activateIgnoringOtherApps))
        }
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let nameItem = NSMenuItem(title: "Name This Space…", action: #selector(nameThisSpace), keyEquivalent: "")
        nameItem.target = self
        nameItem.isEnabled = UserDefaults.standard.bool(forKey: Preferences.spaceLabelsEnabledKey)
        menu.addItem(nameItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Mission Control Launcher",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        if let button = statusItem?.button, let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }

    /// Opens the naming box while the panel is still up, so this app is active when the box
    /// takes focus; the panel closes as the box becomes key. Closing the panel first left an
    /// accessory app with no window, macOS handed activation to the previous app, and typing
    /// went there instead of into the box.
    @objc func nameThisSpace() {
        spaceLabels.renameActiveSpace()
        closePopover()
    }

    // MARK: - Settings Window

    @objc func openSettings() {
        closePopover()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
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
        activateSelf()
    }

    // MARK: - Launchers (no permission needed)

    func triggerMissionControl() {
        launch(SystemApp.missionControl)
    }

    func triggerAppLauncher() {
        launch(SystemApp.appLauncher)
    }

    func triggerScreenshot() {
        launch(SystemApp.screenshot)
    }

    private func launch(_ app: SystemApp) {
        closePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            app.open()
        }
    }

    // MARK: - Synthesized shortcuts (need Accessibility)

    /// ⌃ plus an arrow key. macOS registers its arrow shortcuts (App Exposé ⌃↓, move a Space
    /// ⌃← ⌃→) with the Fn flag too, since a real arrow key carries it; a synthesized arrow
    /// with Control alone does not match and nothing happens.
    private static let controlArrow: CGEventFlags = [.maskControl, .maskSecondaryFn]

    /// App Exposé is ⌃↓. It shows the windows of the *active* app, which is us while the
    /// panel is open, so activation goes back to the user's app first. A sandboxed app has
    /// no other route: the launch arguments Mission Control.app accepts are stripped.
    func triggerAppExpose() {
        guard ensureAccessibility() else { return }
        closePopover()
        let previous = lastFrontmostApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previous {
                self.activate(previous, allWindows: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.postShortcut(keyCode: CGKeyCode(kVK_DownArrow), flags: Self.controlArrow)
            }
        }
    }

    /// Show Desktop's shortcut is F11. ⌘F3 only works on Apple keyboards through the
    /// physical media key, so a synthesized ⌘F3 does nothing.
    func triggerShowDesktop() {
        synthesize(keyCode: CGKeyCode(kVK_F11), flags: [])
    }

    func triggerPreviousSpace() {
        synthesize(keyCode: CGKeyCode(kVK_LeftArrow), flags: Self.controlArrow)
    }

    func triggerNextSpace() {
        synthesize(keyCode: CGKeyCode(kVK_RightArrow), flags: Self.controlArrow)
    }

    func triggerSpotlight() {
        synthesize(keyCode: CGKeyCode(kVK_Space), flags: .maskCommand)
    }

    private func synthesize(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard ensureAccessibility() else { return }
        closePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.postShortcut(keyCode: keyCode, flags: flags)
        }
    }

    // MARK: - Running apps

    func focusApp(_ app: NSRunningApplication) {
        closePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.activate(app, allWindows: true)
        }
    }

    func focusWindow(_ window: AppWindow, of app: NSRunningApplication) {
        closePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            WindowLister.raise(window)
            self.activate(app, allWindows: false)
        }
    }

    /// `NSRunningApplication.terminate()` sends a Quit Apple event, which the App Sandbox
    /// blocks (it returns false). Fall back to sending ⌘Q straight to that process.
    func quitApp(_ app: NSRunningApplication) {
        if app.terminate() { return }
        guard ensureAccessibility() else { return }
        postShortcut(keyCode: CGKeyCode(kVK_ANSI_Q), flags: .maskCommand, toPid: app.processIdentifier)
    }

    // MARK: - Accessibility

    func requestAccessibility() {
        _ = ensureAccessibility()
    }

    /// Synthesizing keyboard events needs Accessibility access. Rather than silently doing
    /// nothing, ask for it and show Settings, where the status is visible.
    private func ensureAccessibility() -> Bool {
        if AccessibilityAccess.isGranted { return true }
        closePopover()
        AccessibilityAccess.request()
        openSettings()
        return false
    }

    /// Posts a key down/up pair. With `toPid` the events go to that process only (used for ⌘Q);
    /// without it they enter the system event stream, where the Dock's shortcuts pick them up.
    private func postShortcut(keyCode: CGKeyCode, flags: CGEventFlags, toPid pid: pid_t? = nil) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { continue }
            event.flags = flags
            if let pid {
                event.postToPid(pid)
            } else {
                event.post(tap: .cghidEventTap)
            }
        }
    }
}

extension AppDelegate: PopoverActions {}
