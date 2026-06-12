#!/bin/bash
# Render the app icon natively and build resources/icon.icns. No Python.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools"
WORK="$(mktemp -d)"
PNG="$WORK/icon-1024.png"
ICONSET="$WORK/icon.iconset"

echo "→ Compiling renderer…"
clang -fobjc-arc -O2 \
  -framework CoreGraphics -framework ImageIO -framework CoreFoundation -framework CoreServices \
  -o "$WORK/makeicon" "$TOOLS/makeicon.m"

echo "→ Rendering 1024×1024…"
"$WORK/makeicon" "$PNG"

echo "→ Building iconset…"
mkdir -p "$ICONSET"
for sz in 16 32 64 128 256 512 1024; do
  sips -z $sz $sz "$PNG" --out "$ICONSET/tmp-$sz.png" >/dev/null
done
cp "$ICONSET/tmp-16.png"   "$ICONSET/icon_16x16.png"
cp "$ICONSET/tmp-32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/tmp-32.png"   "$ICONSET/icon_32x32.png"
cp "$ICONSET/tmp-64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/tmp-128.png"  "$ICONSET/icon_128x128.png"
cp "$ICONSET/tmp-256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/tmp-256.png"  "$ICONSET/icon_256x256.png"
cp "$ICONSET/tmp-512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/tmp-512.png"  "$ICONSET/icon_512x512.png"
cp "$ICONSET/tmp-1024.png" "$ICONSET/icon_512x512@2x.png"
rm -f "$ICONSET"/tmp-*.png

echo "→ iconutil → resources/icon.icns…"
mkdir -p "$ROOT/resources"
iconutil -c icns "$ICONSET" -o "$ROOT/resources/icon.icns"
cp "$PNG" "$ROOT/resources/icon-preview.png"   # for quick visual review
echo "✓ resources/icon.icns built"
