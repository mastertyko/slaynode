#!/bin/bash
set -euo pipefail

# Build script for SlayNodeMenuBar
# Creates a .app bundle in the project root

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Slaynode"
APP_DIR="${ROOT_DIR}/${APP_NAME}.app"
EXECUTABLE_NAME="SlayNodeMenuBar"
CONFIGURATION="${1:-debug}"
ARCH_DIR="arm64-apple-macosx"

echo "🔨 Building SlayNodeMenuBar (${CONFIGURATION})..."
swift build -c "${CONFIGURATION}"

PRODUCT_DIR="${ROOT_DIR}/.build/${ARCH_DIR}/${CONFIGURATION}"
BINARY_PATH="${PRODUCT_DIR}/${EXECUTABLE_NAME}"
RESOURCE_BUNDLE="${PRODUCT_DIR}/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"

if [[ ! -f "${BINARY_PATH}" ]]; then
  echo "❌ Binary not found at ${BINARY_PATH}" >&2
  exit 1
fi

echo "📦 Creating app bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en-US</string>
    <key>CFBundleExecutable</key>
    <string>SlayNodeMenuBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.slaynode.menubar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Slaynode</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# Copy executable
cp "${BINARY_PATH}" "${APP_DIR}/Contents/MacOS/"
chmod +x "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"

# Copy resources
if [[ -d "${RESOURCE_BUNDLE}" ]]; then
  cp -R "${RESOURCE_BUNDLE}"/* "${APP_DIR}/Contents/Resources/"
fi

# Create AppIcon.icns from iconset
ICONSET_PATH="${APP_DIR}/Contents/Resources/AppIcon.iconset"
if [[ -d "${ICONSET_PATH}" ]]; then
  echo "🎨 Creating AppIcon.icns..."
  # Copy iconset from Sources to Resources first
  cp -r "${ROOT_DIR}/Sources/SlayNodeMenuBar/Resources/AppIcon.iconset" "${APP_DIR}/Contents/Resources/"
  iconutil -c icns "${ICONSET_PATH}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
  if [[ -f "${APP_DIR}/Contents/Resources/AppIcon.icns" ]]; then
    echo "✅ AppIcon.icns created successfully"
  else
    echo "❌ Failed to create AppIcon.icns"
  fi
fi

# Code sign the app
echo "🔐 Code signing app..."
codesign --force --sign - "${APP_DIR}"

echo "✅ ${APP_NAME}.app is ready at: ${APP_DIR}"
echo "🚀 Run with: open '${APP_DIR}'"
