#!/bin/sh
# Regenerates every macOS app icon size from appstore/icon/AppIcon.svg into the asset
# catalog. The Mac App Store requires all ten slots (16/32/128/256/512 at 1x and 2x);
# shipping only some of them fails upload validation with "missing required icon".
# Needs rsvg-convert (brew install librsvg).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SVG="$HERE/AppIcon.svg"
SET="$HERE/../../MissionControl/MissionControl/Assets.xcassets/AppIcon.appiconset"
command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found: brew install librsvg" >&2; exit 1; }

render() { # <pixels> <filename>
  rsvg-convert -w "$1" -h "$1" -o "$SET/$2" "$SVG"
  echo "  $2  ($1x$1)"
}
echo "rendering icons from $(basename "$SVG"):"
render 16   AppIcon-16.png
render 32   AppIcon-16@2x.png
render 32   AppIcon-32.png
render 64   AppIcon-32@2x.png
render 128  AppIcon-128.png
render 256  AppIcon-128@2x.png
render 256  AppIcon-256.png
render 512  AppIcon-256@2x.png
render 512  AppIcon-512.png
render 1024 AppIcon-512@2x.png
