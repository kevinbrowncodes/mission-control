//
//  AccessibilityAccess.swift
//  MissionControl
//
//  Checking and requesting the Accessibility permission that synthesized key events need.
//

import AppKit
import ApplicationServices

enum AccessibilityAccess {
    private static let promptedKey = "didPromptForAccessibility"

    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt the first time. macOS shows that prompt only once per app,
    /// so on later requests open the Accessibility pane directly instead.
    static func request() {
        if UserDefaults.standard.bool(forKey: promptedKey) {
            openSystemSettingsPane()
        } else {
            UserDefaults.standard.set(true, forKey: promptedKey)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    static func openSystemSettingsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
