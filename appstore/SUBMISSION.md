# Mission Control Launcher — App Store submission

Mac App Store listing, screenshots and the resubmission after the Guideline 4.2 rejection.

## Why 1.0 was rejected, and what changed

Apple's first review returned **4.2.0 Design: Minimum Functionality (macOS)**. That build had one function: clicking the icon opened Mission Control, which the reviewer read as a launcher for a built-in feature.

Build 2 is a panel, not a button:

| Area | What it does | Permission |
|---|---|---|
| Quick actions | Mission Control, Apps (Launchpad on macOS 15 and earlier), Screenshot toolbar | none |
| Quick actions | App Exposé, Show Desktop, Previous/Next Space, Spotlight | Accessibility |
| Running apps | List with icons, count, type-to-filter; click to switch (un-hides too); frontmost marker | none |
| Running apps | Hover to quit an app | Accessibility |
| Space names | Name the current Space from the panel's THIS SPACE row; while Mission Control is open each named Space's thumbnail is filled with its name | none |
| Global shortcut | ⌃⌥M opens the panel from any app (toggle in Settings) | none |
| Settings | Open at Login, shortcut toggle, live Accessibility status with Grant / Open System Settings | none |

The listing copy and the reviewer notes in `asc_meta.json` explain who this is for: remote users on Screen Sharing / VNC / RDP whose clients swallow gestures, function keys and hot corners, and people on PC keyboards without a Mission Control key.

### Suggested Resolution Center reply

> Thank you for the review. We have submitted build 2, which replaces the single-action button with a full panel: eight quick actions (Mission Control, Apps, App Exposé, Show Desktop, previous/next Space, Spotlight, Screenshot), Space names that fill each Space's thumbnail in Mission Control, a running-apps switcher with type-to-filter and quit, a global shortcut (⌃⌥M) and a Settings window. The app exists for remote users (Screen Sharing, VNC, RDP) and people on PC keyboards, for whom the trackpad swipe, the Mission Control key and hot corners never reach the Mac; the panel gives them all of that back as clicks. Details and testing steps are in the review notes.

## Screenshots (Mac, 2880×1800)

Shot on the Mac Studio 2022 through Hands (2026-11-09): five staged Spaces named Research (Safari on Wikipedia's "Mission control center"), Writing (TextEdit notes), Budget (Calculator), Time Zones (Clock) and Design (Font Book). Nothing personal on screen and no Apple product imagery.

| # | File | What's on screen | Caption | Subcaption |
|---|---|---|---|---|
| 1 | `01-hero` | The panel open over Research (full screen) | Mission Control, **one click away** | A menu bar panel for the desktop overview, your Spaces and your apps. Even when you're remoted in. |
| 2 | `02-names` | Mission Control: RESEARCH · WRITING · BUDGET · TIME ZONES · DESIGN fill the Spaces bar | Name your **Spaces** | The name fills each thumbnail in Mission Control, so you always know which desktop is which. |
| 3 | `03-remote` | The panel's quick actions, cropped | Your keys. **Their Mac.** | From a PC or over remote desktop, ⌃↑ and ⌘Space can open the wrong computer's Mission Control or search. A click always lands on the Mac you're controlling. |
| 4 | `04-naming` | The Name This Space box | Naming takes **one click** | This Space ▸ Name…, type a name, press Return. It shows in Mission Control straight away. |

Every caption is true in its shot; nothing shows ratings, prices or other platforms.

### Regenerate

The raws are full-screen Hands looks from the Studio (`screenshots/raw/mac/studio-*.png`, scaled to 2880 wide). `render-mac.sh --skip-raws` composes them from `screenshots/shots-mac.json`: `"layout": "top"` puts the caption above a full-width screen, otherwise the caption sits left of a crop. Without `--skip-raws` it also renders the panel and Settings views offscreen (unused by the current shots).

```sh
appstore/screenshots/render-mac.sh --skip-raws
open appstore/screenshots/out/mac/contact-sheet.png
```

Spec: 16:10, one of 1280×800 / 1440×900 / 2560×1600 / 2880×1800, PNG without alpha, up to 10. Don't commit `contact-sheet.png`.

## App preview (1920×1080, about 20 s)

Hands records at 4 fps, so the preview is cut from Hands' 4K stills: `appstore/preview/stills/` (scaled to 1920×1080), a slow zoom on each, 0.4 s crossfades, SF Pro caption bars drawn by `captions.swift`, an end card and a silent stereo track. `python3 appstore/preview/make_preview.py` writes `appstore/preview/preview.mp4` (not committed). Launch uploads it: the `previews` map in `asc_meta.json` names the file and the poster frame (6 s), and `upload-previews` replaces the DESKTOP preview set. `previews` shows App Store Connect's processing state.

## Upload

Uses [Launch](https://github.com/kevinbrowncodes/launch) (`~/Documents/GitHub/kevinbrowncodes/launch`, formerly ascpilot), where Mission Control is registered as `mission-control-launcher`. One-time: the API key in `~/.appstoreconnect/private_keys/` and `issuer_id` in `~/.appstoreconnect/ascpilot.json` (see its README). `launch asc` takes the meta path and bundle ID from Launch's registry, so the commands work from anywhere (the screenshot and preview paths inside the meta file are relative to the meta file):

```sh
export ASC_PLATFORM=MAC_OS
L="$HOME/Documents/GitHub/kevinbrowncodes/launch/bin/launch asc mission-control-launcher"

$L verify              # key + app record wired up
$L status              # version state; must be editable (Rejected / Prepare for Submission)
$L set-subtitle
$L set-version-meta    # description, keywords, promo text, ©, URLs
$L set-review-details  # contact + the review notes above
$L upload-screenshots  # replaces the APP_DESKTOP set with out/mac/01–04 (order in asc_meta.json)
./appstore/upload-mac.sh                # archive + upload build 2 (Launch's upload.sh is iOS-only)
python3 appstore/preview/make_preview.py && $L upload-previews   # the app preview ($L previews for state)
$L attach-build        # once processing shows VALID
$L submit
```

Manual alternative: App Store Connect ▸ Mission Control Launcher ▸ 1.0 ▸ **Mac** ▸ App Previews and Screenshots, drag `01-hero.png` … `04-naming.png` in that order, and the preview video.

### What went wrong on the first attempt (2026-09-05)

The 1.0 record went to **Invalid Binary** after a resubmission that carried only the new screenshots. `asc.py status` showed why: the version still had build 1 (the single-action app that drew the 4.2 rejection), no subtitle, no promotional text, the old description and keywords, `copyright 'FlexKey LLC'` and `support https://www.flexkeyapp.com` — another app's values. Only `upload-screenshots` had been run.

Two build defects were found and fixed at the same time:

- **Incomplete app icon.** The asset catalog declared all ten macOS slots but held one file (1024 px), so `Assets.car` shipped a single rendition. A Mac App Store binary needs 16/32/128/256/512 at 1x and 2x. `appstore/icon/render-icons.sh` now renders all ten from `appstore/icon/AppIcon.svg`; the rebuilt archive carries ten renditions. (The four-entry `AppIcon.icns` Xcode also emits is normal — Xcode.app and Calculator.app ship exactly the same four.)
- **No export-compliance answer.** `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` was missing, which stops a submission on the encryption question. Added, along with the empty `NSHumanReadableCopyright`.

So the order below matters: metadata *and* build, then attach, then submit.

Before uploading:
- `support_url` / `privacy_policy_url` point at this repo (`PRIVACY.md`, `develop` branch). The repo is public, but **`PRIVACY.md` must be pushed** or the privacy URL 404s during review.
- The Accessibility actions were verified end to end on the Mac Studio 2022 through Hands with the permission granted (2026-11-09): Mission Control, Next/Previous Space and Spotlight work. That run found that a sandboxed app can't read other apps' windows (`kAXErrorCannotComplete`), so the per-app window list was removed for 1.0.
