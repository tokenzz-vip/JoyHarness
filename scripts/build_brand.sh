#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/joyharness-brand.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# The app consumes the checked-in assets. These tools are only needed when
# rebuilding the editable SVG identity, not when building or running the app.
command -v magick >/dev/null || { echo 'ImageMagick is required to export brand assets' >&2; exit 1; }
python3 - "$ROOT" <<'PY'
import re
import sys
from pathlib import Path
brand = Path(sys.argv[1]) / "assets/brand"
master = (brand / "joyharness-icon.svg").read_text()
small = re.sub(r'  <g[^>]*data-detail="large"[^>]*>.*?</g>\n', '', master, flags=re.S)
(brand / "joyharness-icon-small.svg").write_text(small)
PY
qlmanage -t -s 1024 -o "$WORK" "$ROOT/assets/brand/joyharness-icon.svg" "$ROOT/assets/brand/joyharness-icon-small.svg" "$ROOT/assets/brand/joyharness-mark.svg" >/dev/null
magick "$WORK/joyharness-icon.svg.png" -alpha on -transparent white "$ROOT/assets/brand/joyharness-icon.png"
magick "$WORK/joyharness-icon-small.svg.png" -alpha on -transparent white "$ROOT/assets/brand/joyharness-icon-small.png"
magick "$WORK/joyharness-mark.svg.png" -alpha on -transparent white -resize 512x512 "$ROOT/assets/brand/joyharness-mark.png"
swift "$ROOT/scripts/generate_icon.swift" "$WORK/JoyHarness.iconset"
iconutil -c icns "$WORK/JoyHarness.iconset" -o "$ROOT/assets/brand/JoyHarness.icns"
echo 'Brand PNG and ICNS exports rebuilt.'
