#!/usr/bin/env bash
# Build Mindo as a proper macOS .app bundle. Output: build/Mindo.app
# Run from anywhere; resolves paths off this script's location.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="Mindo"
APP_DIR="build/$APP_NAME.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
[ -f "$BIN_PATH" ] || { echo "binary not found at $BIN_PATH"; exit 1; }

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Drag in localized resources + the Mindo SPM resource bundle.
RES_BUNDLE_DIR="$(dirname "$BIN_PATH")"
if [ -d "$RES_BUNDLE_DIR/Mindo_Mindo.bundle" ]; then
    cp -R "$RES_BUNDLE_DIR/Mindo_Mindo.bundle" "$APP_DIR/Contents/Resources/"
fi

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>          <string>com.mindo.Mindo</string>
    <key>CFBundleName</key>                <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>         <string>$APP_NAME</string>
    <key>CFBundleVersion</key>             <string>0.1</string>
    <key>CFBundleShortVersionString</key>  <string>0.1</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSPrincipalClass</key>            <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>     <string>Mind Map</string>
            <key>CFBundleTypeExtensions</key><array><string>mmd</string></array>
            <key>CFBundleTypeRole</key>     <string>Editor</string>
            <key>LSItemContentTypes</key>   <array><string>public.text</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>     <string>Markdown</string>
            <key>CFBundleTypeExtensions</key><array><string>md</string></array>
            <key>CFBundleTypeRole</key>     <string>Editor</string>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>     <string>PlantUML</string>
            <key>CFBundleTypeExtensions</key><array><string>puml</string></array>
            <key>CFBundleTypeRole</key>     <string>Editor</string>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>     <string>FreeMind</string>
            <key>CFBundleTypeExtensions</key><array><string>mm</string></array>
            <key>CFBundleTypeRole</key>     <string>Viewer</string>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "==> done: open '$APP_DIR'"
echo "    or run directly: '$APP_DIR/Contents/MacOS/$APP_NAME'"
