#!/bin/bash
# Local quality gate (no hosted CI). Runs on every push via scripts/hooks/pre-push
# (enable per clone: git config core.hooksPath scripts/hooks).
set -euo pipefail

cd "$(dirname "$0")/.."

# ── Gate: store metadata fits App Store Connect's limits ─────────────────────
# Launch sends these fields as-is; an over-long one fails mid-release, after
# the build is uploaded. Limits are Apple's, not ours.
python3 - <<'PY'
import json, sys
m = json.load(open("appstore/asc_meta.json"))
limits = {"name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170,
          "description": 4000, "whats_new": 4000, "review_notes": 4000}
bad = [f"{k} is {len(m[k])} chars (limit {n})" for k, n in limits.items()
       if k in m and len(m[k]) > n]
if bad:
    sys.exit("✗ appstore/asc_meta.json exceeds App Store Connect limits:\n  "
             + "\n  ".join(bad) + "\n  Fix: shorten the field; the limit is Apple's.")
print("✓ store metadata within App Store Connect limits")
PY

# ── Gate: the app builds ─────────────────────────────────────────────────────
DERIVED=$(mktemp -d)
trap 'rm -rf "$DERIVED"' EXIT
if ! xcodebuild -project MissionControl/MissionControl.xcodeproj -scheme MissionControl \
     -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
     build -quiet >"$DERIVED/build.log" 2>&1; then
  grep -E "error:" "$DERIVED/build.log" | head -20
  echo "✗ the Release build failed (errors above)."
  echo "  Fix: make it build in Xcode before pushing."
  exit 1
fi
echo "✓ Release build succeeds"
