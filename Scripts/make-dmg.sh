#!/usr/bin/env bash
# Wrap build/Kep.app into a distributable DMG (build/Kep.dmg).
# Usage: ./Scripts/make-dmg.sh [version]
#
# Composition: a single read-write staging dir with the .app + a symlink to
# /Applications, then `hdiutil create` snapshots it into a UDIF zlib-
# compressed image. No notarization step here — that requires Developer ID
# credentials; the resulting DMG is fine for ad-hoc local testing or for
# feeding into a separate `notarytool submit` pipeline.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="${1:-0.1}"
APP_NAME="kep"
APP_PATH="build/$APP_NAME.app"
DMG_PATH="build/$APP_NAME-$VERSION.dmg"

if [ ! -d "$APP_PATH" ]; then
    echo "==> $APP_PATH not found — building it first"
    "$SCRIPT_DIR/make-app.sh"
fi

STAGE_DIR="$(mktemp -d)/dmg-stage"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE_DIR" \
    -format UDZO \
    -fs HFS+ \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGE_DIR"

SIZE="$(du -h "$DMG_PATH" | cut -f1)"
echo "==> wrote $DMG_PATH ($SIZE)"
echo "    To distribute notarized: codesign --deep --options runtime $APP_PATH"
echo "    then xcrun notarytool submit $DMG_PATH --apple-id … --wait"
