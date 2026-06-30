#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="HTML Agent Editor"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "=== HTML Agent Editor Build ==="
echo "Project: $PROJECT_DIR"
echo "Output: $APP_BUNDLE"
echo ""

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

SRC="$PROJECT_DIR/Sources"
SOURCE_FILES=(
    "$SRC/main.swift"
    "$SRC/AppDelegate.swift"
    "$SRC/ViewController.swift"
    "$SRC/TerminalView.swift"
)

echo "Compiling with swiftc..."
swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/HTMLEditor" \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -framework Cocoa \
    -framework WebKit \
    "${SOURCE_FILES[@]}"

echo "Copying resources..."
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc sign
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

# Copy to Desktop
FINAL_PATH="$HOME/Desktop/$APP_NAME.app"
rm -rf "$FINAL_PATH"
cp -R "$APP_BUNDLE" "$FINAL_PATH"

echo ""
echo "✅ Build complete!"
echo "App at: $FINAL_PATH"
echo ""
echo "Size: $(du -sh "$FINAL_PATH" | cut -f1)"
echo "Binary: $(file "$APP_BUNDLE/Contents/MacOS/HTMLEditor" | sed 's/.*: //')"
echo ""
