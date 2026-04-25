#!/usr/bin/env bash
# Build Resources/AppIcon.icns from a source PNG (1024×1024 recommended).
# Usage: ./Scripts/make-icon.sh [source.png]
# Defaults to ../javamind/DemoWorkspace/app.png so first-run setup just works.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

SRC="${1:-../javamind/DemoWorkspace/app.png}"
[ -f "$SRC" ] || { echo "icon source not found: $SRC"; exit 1; }

ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Per Apple's icon-set spec: 16, 32, 128, 256, 512 with @2x variants.
declare -a SIZES=(
    "16   icon_16x16.png"
    "32   icon_16x16@2x.png"
    "32   icon_32x32.png"
    "64   icon_32x32@2x.png"
    "128  icon_128x128.png"
    "256  icon_128x128@2x.png"
    "256  icon_256x256.png"
    "512  icon_256x256@2x.png"
    "512  icon_512x512.png"
    "1024 icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
    size="${entry%% *}"
    name="${entry##* }"
    sips -z "$size" "$size" "$SRC" --out "$ICONSET_DIR/$name" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns
echo "==> wrote Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
