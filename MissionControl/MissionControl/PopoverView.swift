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
    func focusWindow(_ window: AppWindow, of app: NSRunningApplication)
    func quitApp(_ app: NSRunningApplication)
}

// MARK: - Main Popover View

struct MainPopoverView: View {
    let actions: PopoverActions

    @State private var runningApps: [NSRunningApplication]
    /// The app that was in front before the popover took focus.
    @State private var frontmostPID: pid_t?
    @State private var expandedPID: pid_t?
    @State private var filter = ""
    private let hasAccessibility: Bool

    private let workspaceCenter = NSWorkspace.shared.notificationCenter

    init(actions: PopoverActions,
         frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
         hasAccessibility: Bool = AccessibilityAccess.isGranted,
         expandedApp: NSRunningApplication? = nil) {
        self.actions = actions
        self.hasAccessibility = hasAccessibility
        _runningApps = State(initialValue: Self.currentRunningApps())
        _frontmostPID = State(initialValue: frontmostApp?.processIdentifier)
        _expandedPID = State(initialValue: expandedApp?.processIdentifier)
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
            Text("Mission Control")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            Button { actions.openSettings() } label: {
                Image(systemName: "gear")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                            let isExpanded = expandedPID == app.processIdentifier
                            RunningAppRow(app: app,
                                          isFrontmost: app.processIdentifier == frontmostPID,
                                          isExpanded: isExpanded) {
                                actions.focusApp(app)
                            } onToggleWindows: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    expandedPID = isExpanded ? nil : app.processIdentifier
                                }
                            } onQuit: {
                                actions.quitApp(app)
                            }
                            if isExpanded {
                                WindowListView(app: app, hasAccessibility: hasAccessibility) { window in
                                    actions.focusWindow(window, of: app)
                                } onRequestAccess: {
                                    actions.requestAccessibility()
                                }
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
        let expanded: CGFloat = expandedPID == nil ? 0 : 110
        return min(rows + expanded + 8, 230)
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
            .help("Quit Mission Control")
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
    let isExpanded: Bool
    let onFocus: () -> Void
    let onToggleWindows: () -> Void
    let onQuit: () -> Void

    @State private var isHovered = false

    private var icon: NSImage {
        app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleWindows) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide windows" : "Show windows")

            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text(app.localizedName ?? "Unknown")
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)

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
        .onHover { hovered in withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovered } }
    }
}

// MARK: - Window List

/// The windows of one app, shown beneath its row. Created only when the user expands the
/// row, so the Accessibility query runs for that app alone.
struct WindowListView: View {
    let app: NSRunningApplication
    let hasAccessibility: Bool
    let onSelect: (AppWindow) -> Void
    let onRequestAccess: () -> Void

    @State private var windows: [AppWindow]

    init(app: NSRunningApplication, hasAccessibility: Bool,
         onSelect: @escaping (AppWindow) -> Void, onRequestAccess: @escaping () -> Void) {
        self.app = app
        self.hasAccessibility = hasAccessibility
        self.onSelect = onSelect
        self.onRequestAccess = onRequestAccess
        _windows = State(initialValue: hasAccessibility ? WindowLister.windows(of: app) : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !hasAccessibility {
                Button(action: onRequestAccess) {
                    Label("Grant Accessibility access to list windows", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            } else if windows.isEmpty {
                Text("No windows")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(windows) { window in
                    WindowRow(window: window) { onSelect(window) }
                }
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 8)
        .padding(.bottom, 4)
    }
}

struct WindowRow: View {
    let window: AppWindow
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: window.isMinimized ? "minus.square" : "macwindow")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)
            Text(window.title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
        .help(window.isMinimized ? "\(window.title) (minimized)" : window.title)
    }
}
