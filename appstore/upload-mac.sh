#!/bin/zsh
# Archives Mission Control for macOS and uploads it to App Store Connect.
#
# Launch's bin/upload.sh is iOS-only (it archives with
# -destination "generic/platform=iOS"), so the Mac build has its own copy here.
# Everything else in the release flow is Launch's; see appstore/SUBMISSION.md.
#
# Needs Xcode signed in to the Apple Developer account (Xcode ▸ Settings ▸ Accounts)
# so -allowProvisioningUpdates can mint the Mac App Store distribution certificate
# and provisioning profile. Run from the repo root.
set -euo pipefail

SCHEME=MissionControl
TEAM=793YF22DGM
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%F)/MissionControl.xcarchive"
PLIST=$(mktemp -t ExportOptions).plist

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>$TEAM</string>
	<key>uploadSymbols</key><true/>
	<key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLISTEOF

mkdir -p "$(dirname "$ARCHIVE")"
xcodebuild archive -project "$HERE/MissionControl/MissionControl.xcodeproj" \
  -scheme "$SCHEME" -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$PLIST" -allowProvisioningUpdates
echo "uploaded — processing takes 5-30 min; check with: asc.py builds"
