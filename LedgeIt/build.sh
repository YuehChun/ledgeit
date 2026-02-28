#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="LedgeIt"
BUILD_DIR=".build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"

echo "Building ${APP_NAME}..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

# Copy binary
cp "${BUILD_DIR}/arm64-apple-macosx/release/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LedgeIt</string>
    <key>CFBundleIdentifier</key>
    <string>com.ledgeit.app</string>
    <key>CFBundleName</key>
    <string>LedgeIt</string>
    <key>CFBundleDisplayName</key>
    <string>LedgeIt</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.finance</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
PLIST

# Copy app icon
cp "LedgeIt/Resources/AppIcon.icns" "${CONTENTS}/Resources/AppIcon.icns"

# Copy resources if they exist
if [ -d "${BUILD_DIR}/arm64-apple-macosx/release/LedgeIt_LedgeIt.bundle" ]; then
    cp -R "${BUILD_DIR}/arm64-apple-macosx/release/LedgeIt_LedgeIt.bundle" "${CONTENTS}/Resources/"
fi

echo ""
echo "App bundle created: ${APP_BUNDLE}"
echo "To run: open ${APP_BUNDLE}"
echo ""

# Optionally open the app
if [ "${1:-}" = "--run" ]; then
    open "${APP_BUNDLE}"
fi
