#!/usr/bin/env bash
# Reset Lamplit on the connected iPhone: uninstall (which takes the app's whole container with it),
# install the last build again, and launch it. Every test round then starts at the first-launch
# screen with no notes, no highlights, no saved settings and no downloaded voice.
#
#   scripts/reset-ios-device.sh            # wipe and reinstall the last build
#   scripts/reset-ios-device.sh --no-launch
#
# The device is found rather than typed: one physical iPhone on the cable, or UDID=… to choose.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="au.com.onyxit.lamplit.dev"
APP="$ROOT/target/ios/DerivedData/Build/Products/Release-iphoneos/Bible.app"
LAUNCH=1
[[ "${1:-}" == "--no-launch" ]] && LAUNCH=0

[[ -d "$APP" ]] || { echo "no device build at $APP: run scripts/build-ios.sh --device first" >&2; exit 1; }

# The phone, by UDID. Simulators report a "simulated" transport and are skipped.
# The name column holds spaces, so the identifier is picked out by its shape rather than position.
UDID="${UDID:-$(xcrun devicectl list devices 2>/dev/null | grep 'physical' |
  grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}' | head -1)}"
[[ -n "$UDID" ]] || { echo "no iPhone on the cable" >&2; exit 1; }
echo "device $UDID"

# Uninstalling is the reset: the container, and with it settings, notes and the voice, goes too.
xcrun devicectl device uninstall app --device "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
# Say so out loud: a silent failure here would leave the last round's notes and settings in place.
if xcrun devicectl device info apps --device "$UDID" 2>/dev/null | grep -qi lamplit; then
  echo "the app is still installed: the wipe did not happen" >&2; exit 1
fi
echo "wiped"
xcrun devicectl device install app --device "$UDID" "$APP" 2>&1 | grep -E "App installed|bundleID" || true

if [[ "$LAUNCH" == 1 ]]; then
  xcrun devicectl device process launch --device "$UDID" "$BUNDLE" 2>&1 | tail -1
fi
