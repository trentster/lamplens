#!/usr/bin/env bash
# The UX review's screenshots: every screen of the iPhone app in the states a reader meets them,
# for an outside read against Mark's yardstick. PNGs land in target/ux-review/ (git-ignored) beside
# an index.md that names each file and what it shows, and names the screens it could not prove.
#
#   scripts/ios-ux-review.sh                    # iPhone, light, default text, 390 pt wide
#   THEME=dark scripts/ios-ux-review.sh         # (the variations come later)
#
# The test is apps/ios/BibleUITests/Screenshots.swift → UXReview: one launch per screen, straight
# into the state through the launch hooks in Store, and a shot only when the element that proves the
# state is there. A screen that cannot be proved is written into index.md as MISSED and never
# photographed, so a filename cannot claim to show something it does not.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/target/ux-review}"
SIMULATOR="${SIMULATOR:-Bible iPhone 14}"
DEVICE_TYPE="${DEVICE_TYPE:-iPhone 14}"
PREFIX="${PREFIX:-iphone-light-default}"
LOG="$OUT/run.log"

rm -rf "$OUT"
mkdir -p "$OUT"

# The capture is allowed to fail part-way: the shots it took are still worth exporting, and the test
# reports every screen it reached either way.
TEST_RUNNER_BIBLE_UX_REVIEW=1 TESTS=UXReview SIMULATOR="$SIMULATOR" DEVICE_TYPE="$DEVICE_TYPE" \
  "$ROOT/scripts/build-ios.sh" --test >"$LOG" 2>&1 || true

ATTACH="$(mktemp -d)"
xcrun xcresulttool export attachments --path "$ROOT/target/ios/Tests.xcresult" \
  --output-path "$ATTACH" >/dev/null
MANIFEST="$ATTACH/manifest.json"
COUNT="$(plutil -extract 0.attachments raw "$MANIFEST")"
REPORT=""

for ((i = 0; i < COUNT; i++)); do
  FILE="$(plutil -extract "0.attachments.$i.exportedFileName" raw "$MANIFEST")"
  NAME="$(plutil -extract "0.attachments.$i.suggestedHumanReadableName" raw "$MANIFEST")"
  NAME="${NAME%%_*}"
  case "$NAME" in
    # The test's own account of the run, carried out as a text attachment.
    ux-report*) REPORT="$ATTACH/$FILE" ;;
    # Only our own shots: the failure snapshots Xcode adds are named "Synthesized Event …".
    ux-*) cp "$ATTACH/$FILE" "$OUT/$PREFIX-${NAME#ux-}.png" ;;
  esac
done
# The report is the run's own account: keep a copy outside the export before the export goes.
if [[ -n "$REPORT" && -s "$REPORT" ]]; then
  cp "$REPORT" "$OUT/report.txt"
  REPORT="$OUT/report.txt"
fi
rm -rf "$ATTACH"

if [[ -z "$REPORT" || ! -s "$REPORT" ]]; then
  echo "the run left no report behind — the test did not finish" >&2
  exit 1
fi

# index.md comes from the run's own report crossed with the files on disk: a screen is listed as
# captured only when both say so, so a lost export cannot be called a shot.
{
  echo "# UX review — iPhone, light, default text"
  echo
  echo "Simulator: $DEVICE_TYPE, 390 pt wide (Mark's 12 Pro width). One launch per screen, straight"
  echo "into the state, and the shot taken only when the element that proves the state was there."
  echo "Sample study data was made through the store's own setters, in the test data folder."
  echo
  captured=0
  missed=0
  while read -r tag name outcome what; do
    [[ "$tag" == UXREVIEW ]] || continue
    if [[ "$outcome" == CAPTURED && -f "$OUT/$PREFIX-$name.png" ]]; then
      echo "- \`$PREFIX-$name.png\` — $what"
      captured=$((captured + 1))
    else
      echo "- **MISSED: $name** — $what"
      missed=$((missed + 1))
    fi
  done < <(grep '^UXREVIEW ' "$REPORT" || true)
  echo
  echo "$captured captured, $missed missed."
} >"$OUT/index.md"

echo "$OUT"
echo
grep -E '^- ' "$OUT/index.md" | sed 's/^- //'
echo
tail -1 "$OUT/index.md"
