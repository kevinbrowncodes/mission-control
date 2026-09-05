# Mission Control — App Store submission

Mac App Store listing, screenshots and the resubmission after the Guideline 4.2 rejection.

## Why 1.0 was rejected, and what changed

Apple's first review returned **4.2.0 Design: Minimum Functionality (macOS)**. That build had one function: clicking the icon opened Mission Control, which the reviewer read as a launcher for a built-in feature.

Build 2 is a panel, not a button:

| Area | What it does | Permission |
|---|---|---|
| Quick actions | Mission Control, Apps (Launchpad on macOS 15 and earlier), Screenshot toolbar | none |
| Quick actions | App Exposé, Show Desktop, Previous/Next Space, Spotlight | Accessibility |
| Running apps | List with icons, count, type-to-filter; click to switch (un-hides too); frontmost marker | none |
| Running apps | Expand an app to list its windows and raise one; hover to quit an app | Accessibility |
| Global shortcut | ⌃⌥M opens the panel from any app (toggle in Settings) | none |
| Settings | Open at Login, shortcut toggle, live Accessibility status with Grant / Open System Settings | none |

The listing copy and the reviewer notes in `asc_meta.json` explain who this is for: remote users on Screen Sharing / VNC / RDP whose clients swallow gestures, function keys and hot corners, and people on PC keyboards without a Mission Control key.

### Suggested Resolution Center reply

> Thank you for the review. We have submitted build 2, which replaces the single-action button with a full panel: eight quick actions (Mission Control, Apps, App Exposé, Show Desktop, previous/next Space, Spotlight, Screenshot), a running-apps switcher with per-app window lists, type-to-filter and quit, a global shortcut (⌃⌥M) and a Settings window. The app exists for remote users (Screen Sharing, VNC, RDP) and people on PC keyboards, for whom the trackpad swipe, the Mission Control key and hot corners never reach the Mac; the panel gives them all of that back as clicks. Details and testing steps are in the review notes.

## Screenshots (Mac, 2880×1800)

| # | File | What's on screen | Caption | Subcaption |
|---|---|---|---|---|
| 1 | `01-hero` | The whole panel, Finder frontmost | Mission Control, **one click away** | A menu bar button for the desktop overview. Works even when you're remoted in. |
| 2 | `02-actions` | Quick-actions grid, cropped | The gestures remote desktop **swallows** | Mission Control, App Exposé, Show Desktop, Spaces, Spotlight and screenshots. Click, don't swipe. |
| 3 | `03-windows` | Running apps with Finder expanded to its windows | Find any window, **from anywhere** | Every running app with its windows. Click to bring one forward, or quit the app. |
| 4 | `04-settings` | Settings window | Open at login. **Nothing else to set up.** | A global shortcut, a login item, and permissions explained in plain words. |

Shots 1–2 are what search results show. Every caption is true in its shot; nothing shows ratings, prices or other platforms.

### Regenerate

The kit's `shotkit` only knows iPhone and iPad sizes, so Mac shots have their own renderer. It compiles the app's real view code (`PopoverView.swift`, `SettingsView.swift`, …) with `screenshots/render-mac/Render.swift`, renders the views at 4× with SwiftUI's `ImageRenderer`, and composes each canvas from `screenshots/shots-mac.json`.

```sh
appstore/screenshots/render-mac.sh              # raws + composites + contact sheet
appstore/screenshots/render-mac.sh --skip-raws  # captions changed, UI didn't
open appstore/screenshots/out/mac/contact-sheet.png
```

The running-apps section shows whatever is running on the machine that renders; the renderer picks Safari, Finder, Chrome, Xcode or Notes (first one with two or more windows) as the frontmost/expanded app. Window titles need the rendering terminal to have Accessibility access. Don't commit `contact-sheet.png`.

Spec: 16:10, one of 1280×800 / 1440×900 / 2560×1600 / 2880×1800, PNG without alpha, up to 10. `render-mac.sh` writes 2880×1800 with no alpha channel.

## Upload

Uses ascpilot (`~/Documents/GitHub/kevinbrowncodes/ascpilot`). One-time: the API key in `~/.appstoreconnect/private_keys/` and `issuer_id` in `~/.appstoreconnect/ascpilot.json` (see its README). `ASC_META` is resolved from the current directory, so use the absolute path and the commands work from anywhere (the screenshot dirs inside the meta file are relative to the meta file, not to where you run):

```sh
export ASC_PLATFORM=MAC_OS
export ASC_META=~/Documents/GitHub/kevinbrowncodes/mission-control/appstore/asc_meta.json
ASC=~/Documents/GitHub/kevinbrowncodes/ascpilot/bin

python3 $ASC/asc.py verify              # key + app record wired up
python3 $ASC/asc.py status              # version state; must be editable (Rejected / Prepare for Submission)
python3 $ASC/asc.py set-subtitle
python3 $ASC/asc.py set-version-meta    # description, keywords, promo text, ©, URLs
python3 $ASC/asc.py set-review-details  # contact + the review notes above
python3 $ASC/asc.py upload-screenshots  # replaces the APP_DESKTOP set with out/mac/01–04
./appstore/upload-mac.sh                # archive + upload build 2 (ascpilot's upload.sh is iOS-only)
python3 $ASC/asc.py attach-build        # once processing shows VALID
python3 $ASC/asc.py submit
```

Manual alternative: App Store Connect ▸ Mission Control ▸ 1.0 ▸ **Mac** ▸ App Previews and Screenshots, drag `01-hero.png` … `04-settings.png` in that order.

### What went wrong on the first attempt (2026-09-05)

The 1.0 record went to **Invalid Binary** after a resubmission that carried only the new screenshots. `asc.py status` showed why: the version still had build 1 (the single-action app that drew the 4.2 rejection), no subtitle, no promotional text, the old description and keywords, `copyright 'FlexKey LLC'` and `support https://www.flexkeyapp.com` — another app's values. Only `upload-screenshots` had been run.

Two build defects were found and fixed at the same time:

- **Incomplete app icon.** The asset catalog declared all ten macOS slots but held one file (1024 px), so `Assets.car` shipped a single rendition. A Mac App Store binary needs 16/32/128/256/512 at 1x and 2x. `appstore/icon/render-icons.sh` now renders all ten from `appstore/icon/AppIcon.svg`; the rebuilt archive carries ten renditions. (The four-entry `AppIcon.icns` Xcode also emits is normal — Xcode.app and Calculator.app ship exactly the same four.)
- **No export-compliance answer.** `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` was missing, which stops a submission on the encryption question. Added, along with the empty `NSHumanReadableCopyright`.

So the order below matters: metadata *and* build, then attach, then submit.

Before uploading:
- `support_url` / `privacy_policy_url` point at this repo (`PRIVACY.md`, `develop` branch). The repo is public, but **`PRIVACY.md` must be pushed** or the privacy URL 404s during review.
- The Accessibility flow was verified for code paths and sandbox behaviour but not end to end with the permission granted; grant it to a Release build once and try App Exposé, Show Desktop, a window list and Quit before submitting.
