//
//  Preferences.swift
//  MissionControl
//

import Foundation

enum Preferences {
    /// Whether ⌃⌥M opens the panel from anywhere.
    static let hotKeyEnabledKey = "openPanelHotKeyEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [hotKeyEnabledKey: true])
    }
}
