//
//  SettingsView.swift
//  MissionControl
//

import SwiftUI
import Combine
import ServiceManagement

struct SettingsView: View {
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @State private var hasAccessibility = AccessibilityAccess.isGranted
    @AppStorage(Preferences.hotKeyEnabledKey) private var hotKeyEnabled = true

    /// Re-checks the permission while the window is open, since granting it in System
    /// Settings doesn't necessarily bring this window back to the front.
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { enabled in
                        updateLoginItem(enabled: enabled)
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Toggle("Open the panel with ⌃⌥M from any app", isOn: $hotKeyEnabled)
            }

            Section("Permissions") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: hasAccessibility
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundColor(hasAccessibility ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Access")
                        Text(hasAccessibility
                             ? "Granted. App Exposé, Show Desktop, Spaces, Spotlight, window lists and quitting apps are available."
                             : "Needed for App Exposé, Show Desktop, Spaces, Spotlight, window lists and quitting apps.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if !hasAccessibility {
                            Button("Open System Settings…") {
                                AccessibilityAccess.openSystemSettingsPane()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    Spacer()
                    if !hasAccessibility {
                        Button("Grant Access") {
                            AccessibilityAccess.request()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 300)
        .onAppear { refreshAccessibility() }
        .onReceive(poll) { _ in refreshAccessibility() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibility()
        }
    }

    private func refreshAccessibility() {
        hasAccessibility = AccessibilityAccess.isGranted
    }

    private func updateLoginItem(enabled: Bool) {
        // Nothing to do when the toggle already matches reality (e.g. after reverting below).
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't update the login item: \(error.localizedDescription)"
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
