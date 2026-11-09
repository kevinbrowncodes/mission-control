//
//  Preferences.swift
//  MissionControl
//

import Foundation

enum Preferences {
    /// Whether ⌃⌥M opens the panel from anywhere.
    static let hotKeyEnabledKey = "openPanelHotKeyEnabled"

    /// Whether named Spaces show their names in Mission Control.
    static let spaceLabelsEnabledKey = "spaceLabelsEnabled"

    /// Names given to Spaces before, newest first; offered when naming a Space after a restart.
    static let recentSpaceNamesKey = "recentSpaceNames"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [hotKeyEnabledKey: true, spaceLabelsEnabledKey: true])
    }
}
