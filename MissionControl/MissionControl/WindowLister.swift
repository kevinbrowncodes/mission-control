//
//  WindowLister.swift
//  MissionControl
//
//  Lists and raises another app's windows through the Accessibility API.
//

import AppKit
import ApplicationServices

struct AppWindow: Identifiable {
    let id: Int
    let title: String
    let isMinimized: Bool
    let element: AXUIElement
}

enum WindowLister {
    /// The app's windows, front to back. Empty without Accessibility access, or when the app
    /// doesn't answer within the timeout (some apps block on accessibility queries).
    static func windows(of app: NSRunningApplication) -> [AppWindow] {
        guard AccessibilityAccess.isGranted else { return [] }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else {
            return []
        }

        return elements.enumerated().compactMap { index, element in
            let title = attribute(kAXTitleAttribute, of: element) as? String ?? ""
            let subrole = attribute(kAXSubroleAttribute, of: element) as? String ?? ""
            let isMinimized = attribute(kAXMinimizedAttribute, of: element) as? Bool ?? false

            // Keep real windows; drop nameless helpers such as tooltips and panels.
            let isRealWindow = subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
            guard isRealWindow || !title.isEmpty else { return nil }

            return AppWindow(id: index,
                             title: title.isEmpty ? "Untitled" : title,
                             isMinimized: isMinimized,
                             element: element)
        }
    }

    /// Un-minimizes if needed and brings the window to the front of its app.
    static func raise(_ window: AppWindow) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
