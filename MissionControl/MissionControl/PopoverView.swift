//
//  PopoverView.swift
//  MissionControl
//
//  The panel that drops down from the menu bar icon.
//

import SwiftUI
import AppKit
import Combine

/// Everything the panel can ask the app to do. `AppDelegate` is the live implementation;
/// the screenshot renderer supplies a no-op one.
@MainActor
protocol PopoverActions: AnyObject {
    func openSettings()
    func requestAccessibility()
    func triggerMissionControl()
    func triggerAppLauncher()
    func triggerAppExpose()
    func triggerShowDesktop()
    func triggerPreviousSpace()
    func triggerNextSpace()
    func triggerSpotlight()
    func triggerScreenshot()
    func focusApp(_ app: NSRunningApplication)
    func quitApp(_ app: NSRunningApplication)
    func nameThisSpace()
}

// MARK: - Main Popover View

struct MainPopoverView: View {
    let actions: PopoverActions

    @State private var runningApps: [NSRunningApplication]
    /// The app that was in front before the popover took focus.
    @State private var frontmostPID: pid_t?
    @State private var filter = ""
    private let hasAccessibility: Bool
    /// The current Space's name; nil when unnamed. The row is hidden when Space names are off.
    private let spaceName: String?
    private let spaceNamesEnabled: Bool

    private let workspaceCenter = NSWorkspace.shared.notificationCenter

    init(actions: PopoverActions,
         frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
         hasAccessibility: Bool = AccessibilityAccess.isGranted,
         spaceName: String? = nil,
         spaceNamesEnabled: Bool = true) {
        self.actions = actions
        self.hasAccessibility = hasAccessibility
        self.spaceName = spaceName
        self.spaceNamesEnabled = spaceNamesEnabled
        _runningApps = State(initialValue: Self.currentRunningApps())
        _frontmostPID = State(initialValue: frontmostApp?.processIdentifier)
    }

    private static func currentRunningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.localizedName != nil }
            .sorted {
                ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending
            }
    }

    private var visibleApps: [NSRunningApplication] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return runningApps }
        return runningApps.filter { ($0.localizedName ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if spaceNamesEnabled {
                thisSpace
                Divider()
            }
            quickActions
            Divider()
            runningAppsList
            Divider()
            footer
        }
        .frame(width: 340)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(workspaceCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            runningApps = Self.currentRunningApps()
        }
        .onReceive(workspaceCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            runningApps = Self.currentRunningApps()
        }
        .onReceive(workspaceCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { note in
            // Ignore our own activation (showing the popover) so the marker stays on the user's app.
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                frontmostPID = app.processIdentifier
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.3.group")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("Mission Control Launcher")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            Button { actions.openSettings() } label: {
                Image(systemName: "gear")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardActivatable { actions.openSettings() }
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: This Space

    /// The current Space's name and the way to set it. Naming lives here, in the panel,
    /// because a right-click menu is something users don't find.
    private var thisSpace: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("THIS SPACE")
                .padding(.top, 10)
            HStack(spacing: 8) {
                Image(systemName: "rectangle.inset.filled")
                    .foregroundColor(.secondary)
                Text(spaceName ?? "Not named")
                    .foregroundColor(spaceName == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button(spaceName == nil ? "Name\u{2026}" : "Rename\u{2026}") { actions.nameThisSpace() }
                    .controlSize(.small)
                    .help("Name this Space so its name shows in Mission Control")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: Quick Actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("QUICK ACTIONS")
                .padding(.top, 10)

            let launcher = SystemApp.appLauncher

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 4),
                spacing: 8
            ) {
                QuickActionButton(icon: "rectangle.3.group", label: "Mission\nControl",
                                  help: "Show every window and desktop") {
                    actions.triggerMissionControl()
                }
                if let name = launcher.displayName {
                    QuickActionButton(icon: "square.grid.3x3.fill", label: name,
                                      help: "Open \(name)") {
                        actions.triggerAppLauncher()
                    }
                }
                QuickActionButton(icon: "macwindow.on.rectangle", label: "App\nExposé",
                                  help: "Show the windows of the current app (⌃↓)",
                                  needsAccessibility: true, hasAccessibility: hasAccessibility) {
                    actions.triggerAppExpose()
                }
                QuickActionButton(icon: "rectangle.on.rectangle.slash", label: "Show\nDesktop",
                                  help: "Move every window aside (F11)",
                                  needsAccessibility: true, hasAccessibility: hasAccessibility) {
                    actions.triggerShowDesktop()
                }
                QuickActionButton(icon: "arrow.left.square", label: "Previous\nSpace",
                                  help: "Move one Space to the left (⌃←)",
                                  needsAccessibility: true, hasAccessibility: hasAccessibility) {
                    actions.triggerPreviousSpace()
                }
                QuickActionButton(icon: "arrow.right.square", label: "Next\nSpace",
                                  help: "Move one Space to the right (⌃→)",
                                  needsAccessibility: true, hasAccessibility: hasAccessibility) {
                    actions.triggerNextSpace()
                }
                QuickActionButton(icon: "magnifyingglass", label: "Spotlight",
                                  help: "Open Spotlight search (⌘Space)",
                                  needsAccessibility: true, hasAccessibility: hasAccessibility) {
                    actions.triggerSpotlight()
                }
                if SystemApp.screenshot.isAvailable {
                    QuickActionButton(icon: "camera.viewfinder", label: "Screenshot",
                                      help: "Open the Screenshot toolbar (⇧⌘5)") {
                        actions.triggerScreenshot()
                    }
                }
            }
            .padding(.horizontal, 12)

            if !hasAccessibility {
                accessibilityNotice
            }
        }
        .padding(.bottom, 10)
    }

    private var accessibilityNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundColor(.orange)
            Text("Actions marked with a lock need Accessibility access.")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button("Grant…") { actions.requestAccessibility() }
                .controlSize(.mini)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: Running Apps

    private var runningAppsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("RUNNING APPS")
                Spacer()
                Text("\(runningApps.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 16)
            }
            .padding(.top, 10)
            .padding(.bottom, 4)

            if runningApps.count >= 6 {
                TextField("Filter apps", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            if runningApps.isEmpty {
                emptyLabel("No apps running")
            } else if visibleApps.isEmpty {
                emptyLabel("No apps match “\(filter)”")
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(visibleApps, id: \.processIdentifier) { app in
                            RunningAppRow(app: app,
                                          isFrontmost: app.processIdentifier == frontmostPID) {
                                actions.focusApp(app)
                            } onQuit: {
                                actions.quitApp(app)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(height: listHeight)
            }
        }
    }

    /// A ScrollView has no ideal height of its own, so the popover would collapse it.
    /// Size it to its rows, capped so long lists scroll.
    private var listHeight: CGFloat {
        let rows = CGFloat(visibleApps.count) * 36
        return min(rows + 8, 230)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                actions.openSettings()
            } label: {
                Label("Settings", systemImage: "gear")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardActivatable { actions.openSettings() }

            Spacer()

            Text("⌃⌥M opens this panel")
                .font(.caption2)
                .foregroundColor(Color.secondary.opacity(0.7))

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardActivatable { NSApplication.shared.terminate(nil) }
            .help("Quit Mission Control Launcher")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let label: String
    var help: String? = nil
    var needsAccessibility = false
    var hasAccessibility = true
    let action: () -> Void

    @State private var isHovered = false

    private var isLocked: Bool { needsAccessibility && !hasAccessibility }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isHovered ? .white : .accentColor)
                Text(label)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(isHovered ? .white : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(alignment: .topTrailing) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(isHovered ? .white : .orange)
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardActivatable(action)
        .help(helpText)
        .onHover { hovered in withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovered } }
    }

    private var helpText: String {
        let base = help ?? label.replacingOccurrences(of: "\n", with: " ")
        return isLocked ? "\(base). Needs Accessibility access." : base
    }
}

// MARK: - Running App Row

struct RunningAppRow: View {
    let app: NSRunningApplication
    let isFrontmost: Bool
    let onFocus: () -> Void
    let onQuit: () -> Void

    @State private var isHovered = false

    private var icon: NSImage {
        app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text(app.localizedName ?? "Unknown")
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessiblePress(onFocus)

            Spacer()

            if isFrontmost {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .help("Frontmost app")
            }

            if isHovered {
                Button {
                    onQuit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .keyboardActivatable(onQuit)
                .help("Quit \(app.localizedName ?? "app")")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
        .keyboardActivatable(onFocus, label: "Switch to \(app.localizedName ?? "app")")
        .onHover { hovered in withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovered } }
    }
}

// MARK: - Keyboard activation

extension View {
    /// Makes a control work without a mouse: Space or Return runs `action` once it has
    /// keyboard focus.
    /// SwiftUI leaves `.plain` buttons and tap-gesture rows out of keyboard activation on
    /// macOS, so keyboard-only and remote users could focus them but not use them.
    func keyboardActivatable(_ action: @escaping () -> Void, label: String? = nil) -> some View {
        modifier(KeyboardActivatable(action: action, label: label))
    }
}

extension View {
    /// Makes a row's title the accessible button for the row's own action, so VoiceOver and
    /// automation can press it without taking over the row's other buttons.
    func accessiblePress(_ action: @escaping () -> Void) -> some View {
        self.accessibilityAddTraits(.isButton).accessibilityAction { action() }
    }
}

private struct KeyboardActivatable: ViewModifier {
    let action: () -> Void
    let label: String?

    func body(content: Content) -> some View {
        // Keyboard only. An accessibility action here would land on every child of a row
        // (SwiftUI passes it down) and override a child button's own press, so rows name
        // their accessible press on their title instead (see accessiblePress).
        if #available(macOS 14.0, *) {
            content
                .focusable(interactions: .activate)
                .onKeyPress(keys: [.space, .return]) { _ in
                    action()
                    return .handled
                }
                .accessibilityHint(label ?? "")
        } else {
            content
        }
    }
}
