#!/usr/bin/env bash
# Embed and sign Sparkle from the exact SwiftPM-resolved binary artifact.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?app bundle required}"
IDENTITY="${2:?resolved signing identity required}"
MODE="${3:?signing mode required}"
ARCH="${JOY_HARNESS_ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH; use arm64 or x86_64" >&2; exit 1 ;; esac
case "$MODE" in local|distribution) ;; *) echo "Unknown signing mode: $MODE" >&2; exit 1 ;; esac

FRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$FRAMEWORK" ]]; then
  echo 'Sparkle artifact missing; run swift package resolve first.' >&2
  exit 1
fi

DEST="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources"
ditto "$FRAMEWORK" "$DEST"
python3 "$ROOT/scripts/app_architecture.py" thin "$DEST" "$ARCH"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE"

ARGS=(--force --sign "$IDENTITY")
if [[ "$MODE" == distribution ]]; then ARGS+=(--options runtime --timestamp); fi
for target in \
  "$DEST/Versions/B/XPCServices/Installer.xpc" \
  "$DEST/Versions/B/XPCServices/Downloader.xpc" \
  "$DEST/Versions/B/Autoupdate" \
  "$DEST/Versions/B/Updater.app" \
  "$DEST"; do
  codesign "${ARGS[@]}" --preserve-metadata=entitlements "$target"
done
codesign --verify --deep --strict "$DEST"
