#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-${ROOT}/.build/JoyHarness.app}"
MODE="${2:-local}"
CONFIGURATION="${JOY_HARNESS_CONFIGURATION:-release}"
case "$MODE" in local|distribution) ;; *) echo 'Unknown signing mode' >&2; exit 1 ;; esac
case "$CONFIGURATION" in debug|release) ;; *) echo 'Unknown configuration' >&2; exit 1 ;; esac
case "$OUT" in *.app) ;; *) echo 'Output must end in .app' >&2; exit 1 ;; esac
if [[ "$MODE" == distribution ]]; then
  IDENTITY="${JOY_HARNESS_SIGNING_IDENTITY:?Set JOY_HARNESS_SIGNING_IDENTITY}"
  if [[ "$IDENTITY" == - ]]; then
    echo 'Distribution builds require a Developer ID Application signing identity.' >&2
    exit 1
  fi
else
  IDENTITY="${JOY_HARNESS_LOCAL_SIGNING_IDENTITY:-${RC_HARNESS_LOCAL_SIGNING_IDENTITY:-}}"
  if [[ -z "$IDENTITY" || "$IDENTITY" == - ]]; then
    if [[ "${JOY_HARNESS_ALLOW_ADHOC:-0}" == 1 ]]; then IDENTITY=-
    else
      echo 'Set JOY_HARNESS_LOCAL_SIGNING_IDENTITY (or RC_HARNESS_LOCAL_SIGNING_IDENTITY). Run through zsh -ic to load ~/.zshrc.' >&2
      exit 1
    fi
  fi
fi
if [[ "$IDENTITY" != - ]]; then
  MATCH="$(security find-identity -v -p codesigning | awk -v identity="$IDENTITY" '
    $2 ~ /^[0-9A-Fa-f]+$/ {
      name = $0
      sub(/^[^"]*"/, "", name)
      sub(/".*$/, "", name)
      if (toupper($2) == toupper(identity) || name == identity) print $2 " " name
    }')"
  if [[ -z "$MATCH" || "$MATCH" == *$'\n'* ]]; then
    echo 'The configured signing identity must resolve to one valid certificate.' >&2
    exit 1
  fi
  if [[ "$MODE" == distribution && "$MATCH" != *' Developer ID Application: '* ]]; then
    echo 'Distribution builds require a Developer ID Application signing identity.' >&2
    exit 1
  fi
  IDENTITY="${MATCH%% *}"
fi
mkdir -p "$(dirname "$OUT")"
PARENT="$(cd "$(dirname "$OUT")" && pwd -P)"
OUT="$PARENT/$(basename "$OUT")"
STAGE="$(mktemp -d "$PARENT/.joyharness-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/JoyHarness.app"
swift build --package-path "$ROOT" --arch arm64 -c "$CONFIGURATION"
BIN="$(swift build --package-path "$ROOT" --show-bin-path --arch arm64 -c "$CONFIGURATION")/JoyHarness"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/JoyHarness"
cp "$ROOT/Sources/JoyHarness/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/assets/brand/JoyHarness.icns" "$APP/Contents/Resources/JoyHarness.icns"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
if [[ -n "${JOY_HARNESS_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${JOY_HARNESS_VERSION}" "$APP/Contents/Info.plist"
fi
if [[ -n "${JOY_HARNESS_BUILD:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${JOY_HARNESS_BUILD}" "$APP/Contents/Info.plist"
fi
if [[ -n "${JOY_HARNESS_FEEDBACK_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :JoyHarnessFeedbackURL string ${JOY_HARNESS_FEEDBACK_URL}" "$APP/Contents/Info.plist"
fi
ARGS=(--force --sign "$IDENTITY" --identifier vip.tokenzz.joyharness)
if [[ "$MODE" == distribution ]]; then ARGS+=(--options runtime --timestamp); fi
/usr/bin/codesign "${ARGS[@]}" "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
LOCK="$OUT.publish.lock"
if ! /usr/bin/shlock -f "$LOCK" -p "$$"; then
  echo "Another build is publishing $OUT" >&2
  exit 1
fi
trap 'rm -f "$LOCK"; rm -rf "$STAGE"' EXIT
if [[ -L "$OUT" ]]; then echo 'Refusing to replace a symlink' >&2; exit 1; fi
if [[ -e "$OUT" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OUT/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$EXISTING_ID" != vip.tokenzz.joyharness ]]; then echo 'Output is not a JoyHarness bundle' >&2; exit 1; fi
fi
if [[ -e "$OUT" ]]; then mv "$OUT" "$STAGE/previous.app"; fi
if ! mv "$APP" "$OUT" || ! /usr/bin/codesign --verify --deep --strict "$OUT"; then
  if [[ -e "$OUT" && ! -e "$APP" ]]; then
    mv "$OUT" "$STAGE/failed.app" || { trap 'rm -f "$LOCK"' EXIT; exit 1; }
  fi
  if [[ -e "$STAGE/previous.app" ]]; then
    mv "$STAGE/previous.app" "$OUT" || { trap 'rm -f "$LOCK"' EXIT; exit 1; }
  fi
  exit 1
fi
echo "Built $OUT"
