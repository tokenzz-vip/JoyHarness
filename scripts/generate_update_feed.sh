#!/usr/bin/env bash
# Run only after notarization, stapling and final DMG packaging. The private
# Sparkle key is read from stdin or Keychain and is never written to disk.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:?release assets directory required}"
TAG="${2:?release tag required}"
REPO="${3:-tokenzz-vip/JoyHarness}"
ARCH="${4:?target architecture required}"
case "$ARCH" in arm64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac

ARCHIVE="$DIST/JoyHarness-$TAG-macos-$ARCH.dmg"
FEED="$DIST/appcast-$ARCH.xml"
if [[ ! "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo 'Expected a stable vMAJOR.MINOR.PATCH tag.' >&2
  exit 1
fi
if [[ ! -f "$ARCHIVE" ]]; then
  echo 'Final release DMG is missing.' >&2
  exit 1
fi

TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle"
if [[ ! -x "$TOOLS/bin/generate_appcast" ]]; then
  echo 'Sparkle tools missing; run swift package resolve first.' >&2
  exit 1
fi
ARGS=(
  --maximum-deltas 0
  --maximum-versions 1
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/"
  --link "https://github.com/$REPO/releases/tag/$TAG"
  -o "$FEED"
)
STAGE="$(mktemp -d "${DIST}/.joyharness-appcast.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp "$ARCHIVE" "$STAGE/"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" |
    "$TOOLS/bin/generate_appcast" --ed-key-file - "${ARGS[@]}" "$STAGE"
else
  "$TOOLS/bin/generate_appcast" --account vip.tokenzz.rcharness "${ARGS[@]}" "$STAGE"
fi
if [[ ! -f "$FEED" ]]; then
  echo 'No signed architecture-specific appcast was generated.' >&2
  exit 1
fi

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" |
    "$TOOLS/bin/sign_update" --ed-key-file - --verify "$FEED"
else
  "$TOOLS/bin/sign_update" --account vip.tokenzz.rcharness --verify "$FEED"
fi
python3 "$ROOT/scripts/validate_update_feed.py" "$FEED" "$ARCHIVE" "$TAG" "$REPO" "$ARCH"
