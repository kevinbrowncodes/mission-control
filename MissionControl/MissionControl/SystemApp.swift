//
//  SystemApp.swift
//  MissionControl
//
//  Locates Apple's launcher apps, which move between macOS releases.
//

import AppKit

/// One of Apple's launcher apps, looked up by bundle identifier with path fallbacks.
struct SystemApp {
    let bundleIDs: [String]
    let fallbackPaths: [String]

    /// Mission Control.app: /System/Library/CoreServices before macOS 26, /System/Applications since.
    static let missionControl = SystemApp(
        bundleIDs: ["com.apple.exposelauncher"],
        fallbackPaths: ["/System/Applications/Mission Control.app",
                        "/System/Library/CoreServices/Mission Control.app"]
    )

    /// Launchpad up to macOS 15; macOS 26 replaced it with Apps.app.
    static let appLauncher = SystemApp(
        bundleIDs: ["com.apple.launchpad.launcher", "com.apple.apps.launcher"],
        fallbackPaths: ["/System/Library/CoreServices/Launchpad.app",
                        "/System/Applications/Apps.app"]
    )

    /// The Screenshot toolbar (what ⇧⌘5 opens).
    static let screenshot = SystemApp(
        bundleIDs: ["com.apple.screenshot.launcher"],
        fallbackPaths: ["/System/Applications/Utilities/Screenshot.app"]
    )

    var url: URL? {
        for id in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url
            }
        }
        for path in fallbackPaths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    var isAvailable: Bool { url != nil }

    /// The name Finder shows, e.g. "Launchpad" or "Apps" (some system bundles report
    /// their name with the extension still attached, so strip it).
    var displayName: String? {
        url.map { url in
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
    }

    func open() {
        guard let url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }
}
