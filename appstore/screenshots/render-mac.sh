#!/bin/sh
# Renders the Mac App Store screenshots: compiles the app's view sources together with
# render-mac/Render.swift, renders the real views at 4x, and composes out/mac/NN-*.png
# (2880×1800, no alpha). Re-run after any UI change. Needs Xcode's toolchain.
#
#   appstore/screenshots/render-mac.sh            # re-render everything
#   appstore/screenshots/render-mac.sh --skip-raws  # recompose captions only
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../../MissionControl/MissionControl"
BUILD="${TMPDIR:-/tmp}/mission-control-render"
mkdir -p "$BUILD"
swiftc -O -target "$(uname -m)-apple-macos13.0" -o "$BUILD/render" \
  "$SRC/PopoverView.swift" "$SRC/SettingsView.swift" "$SRC/SystemApp.swift" \
  "$SRC/AccessibilityAccess.swift" "$SRC/WindowLister.swift" "$SRC/Preferences.swift" \
  "$HERE/render-mac/Render.swift"
"$BUILD/render" "$HERE/shots-mac.json" "$@"
