#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift test --package-path "$ROOT"
bash -n "$ROOT/scripts/build_app.sh"
bash -n "$ROOT/scripts/embed_sparkle.sh"
bash -n "$ROOT/scripts/generate_update_feed.sh"
bash -n "$ROOT/scripts/package_dmg.sh"
bash -n "$ROOT/scripts/verify_dmg.sh"
PYTHONPYCACHEPREFIX="$ROOT/.build/pycache" \
  python3 -m py_compile "$ROOT/scripts/app_architecture.py" "$ROOT/scripts/validate_update_feed.py"
plutil -lint "$ROOT/Sources/JoyHarness/Info.plist"
