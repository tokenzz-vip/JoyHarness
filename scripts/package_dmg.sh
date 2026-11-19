#!/usr/bin/env bash
set -euo pipefail

APP="${1:?JoyHarness.app path required}"
OUTPUT="${2:?output .dmg path required}"
VOLUME_NAME="${3:-JoyHarness}"

if [[ ! -d "$APP" || "$(basename "$APP")" != JoyHarness.app ]]; then
  echo 'A JoyHarness.app bundle is required.' >&2
  exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" != vip.tokenzz.joyharness ]]; then
  echo 'Unexpected application bundle identifier.' >&2
  exit 1
fi
if [[ "$OUTPUT" != *.dmg || -L "$OUTPUT" || ( -e "$OUTPUT" && ! -f "$OUTPUT" ) ]]; then
  echo 'Output must be a .dmg file and cannot be a symlink.' >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"

mkdir -p "$(dirname "$OUTPUT")"
PARENT="$(cd "$(dirname "$OUTPUT")" && pwd -P)"
OUTPUT="$PARENT/$(basename "$OUTPUT")"
STAGE="$(mktemp -d "$PARENT/.joyharness-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

mkdir "$STAGE/volume"
ditto "$APP" "$STAGE/volume/JoyHarness.app"
ln -s /Applications "$STAGE/volume/Applications"

hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$STAGE/volume" \
  -format UDZO -imagekey zlib-level=9 "$STAGE/image.dmg"
hdiutil verify "$STAGE/image.dmg" >/dev/null
mv -f "$STAGE/image.dmg" "$OUTPUT"
echo "Packaged $OUTPUT"
