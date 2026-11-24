#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_TEST=(swift test --package-path "$ROOT")
if [[ "${JOY_HARNESS_SKIP_CANVAS_LAYOUT_TESTS:-0}" == 1 ]]; then
  # Showing SwiftUI Canvas on macos-15-intel aborts inside Metal (actions/runner-images#15251).
  echo 'Skipping the two layout tests that display the mapping Canvas on macos-15-intel.'
  SWIFT_TEST+=(--skip '^JoyHarnessTests\.(DashboardLayoutTests/testDashboardKeepsMinimumContentSizeAcrossPages|MacrosLayoutTests/testSwitchingToMacrosDoesNotBlockTheMainThread)$')
fi
"${SWIFT_TEST[@]}"
bash -n "$ROOT/scripts/test_all.sh"
bash -n "$ROOT/scripts/build_app.sh"
bash -n "$ROOT/scripts/embed_sparkle.sh"
bash -n "$ROOT/scripts/generate_update_feed.sh"
bash -n "$ROOT/scripts/package_dmg.sh"
bash -n "$ROOT/scripts/verify_dmg.sh"
PYTHONPYCACHEPREFIX="$ROOT/.build/pycache" \
  python3 -m py_compile "$ROOT/scripts/app_architecture.py" "$ROOT/scripts/validate_update_feed.py"
plutil -lint "$ROOT/Sources/JoyHarness/Info.plist"
