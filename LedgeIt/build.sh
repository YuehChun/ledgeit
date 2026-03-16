#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="LedgeIt"
VERSION="${1:-1.0.0}"
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
cat > "${CONTENTS}/Info.plist" << PLIST
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
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
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
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/YuehChun/ledgeit/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>kZOqKEU+ZDo845aJR8eJ5OvhoWDObK1I0+e8XPkoJFY=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
</dict>
</plist>
PLIST

# Copy Sparkle framework and fix rpath
mkdir -p "${CONTENTS}/Frameworks"
cp -R "${BUILD_DIR}/arm64-apple-macosx/release/Sparkle.framework" "${CONTENTS}/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "${CONTENTS}/MacOS/${APP_NAME}" 2>/dev/null || true

# Copy app icon
cp "LedgeIt/Resources/AppIcon.icns" "${CONTENTS}/Resources/AppIcon.icns"

# Copy resources if they exist
if [ -d "${BUILD_DIR}/arm64-apple-macosx/release/LedgeIt_LedgeIt.bundle" ]; then
    cp -R "${BUILD_DIR}/arm64-apple-macosx/release/LedgeIt_LedgeIt.bundle" "${CONTENTS}/Resources/"
fi

echo ""
echo "App bundle created: ${APP_BUNDLE}"

# Create DMG
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
DMG_TEMP="${BUILD_DIR}/dmg-staging"

echo "Creating DMG..."
rm -rf "${DMG_TEMP}" "${DMG_PATH}"
mkdir -p "${DMG_TEMP}"

# Copy app to staging
cp -R "${APP_BUNDLE}" "${DMG_TEMP}/"

# Create symlink to /Applications
ln -s /Applications "${DMG_TEMP}/Applications"

# Create DMG with hdiutil
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_PATH}" 2>&1

rm -rf "${DMG_TEMP}"

echo ""
echo "DMG created: ${DMG_PATH}"
echo "To install: open ${DMG_PATH}"
echo ""

# Optionally open the app or DMG
if [ "${2:-}" = "--run" ]; then
    open "${APP_BUNDLE}"
elif [ "${2:-}" = "--open-dmg" ]; then
    open "${DMG_PATH}"
fi
