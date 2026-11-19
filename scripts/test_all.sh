#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift test --package-path "$ROOT"
bash -n "$ROOT/scripts/build_app.sh"
bash -n "$ROOT/scripts/package_dmg.sh"
plutil -lint "$ROOT/Sources/JoyHarness/Info.plist"
