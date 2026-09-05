# Mission Control

A macOS menu bar utility that puts Mission Control, App Exposé, Show Desktop and your running apps one click away.

## Why

Mission Control is normally reached with a trackpad swipe, a dedicated key or a hot corner. For a lot of people none of those exist, and this app is the difference between having Mission Control and not having it at all:

- **Remote users.** Screen Sharing, Apple Remote Desktop, VNC, RDP and similar clients keep gestures and most function keys for themselves: a three-finger swipe never reaches the Mac, F3 does something on the local machine, and hot corners aren't forwarded. Logging in to a Mac remotely is why this app was written in the first place.
- **Windows / PC keyboards.** No Mission Control or Launchpad key, function keys that map differently, and usually no trackpad.
- **Mice without gestures, KVM switches, docked laptops with the lid closed**, and anyone who just prefers to click.

A menu bar button works in every one of those situations because a click is all it takes.

## What it does

Click the icon in the menu bar (or press ⌃⌥M anywhere) to open the panel:

- **Quick actions** — Mission Control, Apps (Launchpad on macOS 15 and earlier), App Exposé, Show Desktop, Previous/Next Space, Spotlight, and the Screenshot toolbar.
- **Running apps** — every open app with its icon and a live count. Click one to bring it forward (hidden apps are un-hidden), expand it to list its windows and raise one, hover and click ✕ to quit it, or type in the filter field when many are open.
- **Settings** — Open at Login, the ⌃⌥M shortcut toggle, and the live status of the Accessibility permission.

Right-click the icon for Settings and Quit.

### Permissions

Mission Control, Apps and Screenshot need nothing. App Exposé, Show Desktop, Spaces, Spotlight, window lists and quitting an app work by sending the system's own keyboard shortcuts and using the Accessibility API, which macOS only allows once the app has **Accessibility** access (System Settings ▸ Privacy & Security ▸ Accessibility). The app asks the first time you use one of those actions, marks those actions with a small lock until then, and shows the current status in Settings. The App Sandbox leaves no other route: it strips the launch arguments Mission Control.app accepts and blocks the Quit Apple event.

The app is sandboxed and collects no data.

## Development

Built with SwiftUI and AppKit. No dependencies.

### Requirements

- macOS 13.0 or later to run
- Xcode 26 to build

### Building from source

1. Clone the repository:
   ```bash
   git clone https://github.com/kevinbrowncodes/mission-control.git
   ```
2. Open `MissionControl/MissionControl.xcodeproj` in Xcode.
3. Build and Run (⌘R). The app has no Dock icon or main window; look for the icon in the menu bar.

### Source layout

| File | What it holds |
|---|---|
| `MissionControlApp.swift` | App entry point and `AppDelegate`: status item, popover, settings window, system actions |
| `PopoverView.swift` | The panel: quick actions grid and running-apps list |
| `SettingsView.swift` | The Settings window |
| `SystemApp.swift` | Locates Apple's launcher apps across macOS versions (Mission Control.app moved in macOS 26; Launchpad became Apps) |
| `AccessibilityAccess.swift` | Checking and requesting the Accessibility permission |
| `WindowLister.swift` | Lists and raises another app's windows through the Accessibility API |
| `GlobalHotKey.swift` | The ⌃⌥M shortcut (Carbon hot key; works in the sandbox) |
| `Preferences.swift` | UserDefaults keys and defaults |

### App Store assets

`appstore/` holds the store listing text (`asc_meta.json`), the reviewer notes and upload steps (`SUBMISSION.md`), and the screenshot pipeline (`screenshots/render-mac.sh` renders the real views into 2880×1800 Mac App Store shots). The privacy policy is `PRIVACY.md`.

## License

[MIT License](LICENSE)
