//
//  MissionControlApp.swift
//  MissionControl
//
//  Created by Kevin Brown on 2/19/26.
//

import SwiftUI
import ServiceManagement

@main
struct MissionControlApp: App {
    var body: some Scene {
        MenuBarExtra("Mission Control", systemImage: "rectangle.3.group") {
            AppMenu()
        }
        .menuBarExtraStyle(.menu)

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}

struct AppMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Mission Control") {
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "Mission Control"]
            try? task.run()
        }

        Divider()

        Button("Settings...") {
            openWindow(id: "settings")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Mission Control") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
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
