#!/bin/bash
set -euo pipefail

# Build script for SlayNodeMenuBar
# Creates a .app bundle in the project root

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="SlayNode"
APP_DIR="${ROOT_DIR}/${APP_NAME}.app"
EXECUTABLE_NAME="SlayNodeMenuBar"
CONFIGURATION="${1:-debug}"
ARCH_DIR="arm64-apple-macosx"
INFO_PLIST_TEMPLATE="${ROOT_DIR}/XcodeSupport/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

APP_VERSION_DEFAULT="$("${PLIST_BUDDY}" -c 'Print :CFBundleShortVersionString' "${INFO_PLIST_TEMPLATE}")"
APP_BUILD_DEFAULT="$("${PLIST_BUDDY}" -c 'Print :CFBundleVersion' "${INFO_PLIST_TEMPLATE}")"
MIN_SYSTEM_VERSION="$("${PLIST_BUDDY}" -c 'Print :LSMinimumSystemVersion' "${INFO_PLIST_TEMPLATE}")"

APP_VERSION="${SLAYNODE_VERSION:-${APP_VERSION_DEFAULT}}"
APP_BUILD="${SLAYNODE_BUILD_NUMBER:-${APP_BUILD_DEFAULT}}"
SPARKLE_FEED_URL="${SLAYNODE_SPARKLE_FEED_URL:-https://raw.githubusercontent.com/mastertyko/slaynode/main/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SLAYNODE_SPARKLE_PUBLIC_ED_KEY:-}"

SPARKLE_INFO=""
if [[ -n "${SPARKLE_FEED_URL}" && -n "${SPARKLE_PUBLIC_ED_KEY}" ]]; then
  SPARKLE_INFO=$(cat <<EOF
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_ED_KEY}</string>
EOF
)
fi

echo "🔨 Building SlayNodeMenuBar (${CONFIGURATION})..."
echo "🎨 Regenerating brand assets..."
swift generate-icons.swift
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
cat > "${APP_DIR}/Contents/Info.plist" <<EOF
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
    <string>SlayNode</string>
    <key>CFBundleDisplayName</key>
    <string>SlayNode</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_SYSTEM_VERSION}</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>SlayNode needs to monitor running development servers for process management.</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>SlayNode needs to inspect system processes to detect development servers.</string>
${SPARKLE_INFO}
</dict>
</plist>
EOF

# Copy executable and fix rpath for bundled frameworks
cp "${BINARY_PATH}" "${APP_DIR}/Contents/MacOS/"
chmod +x "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"
install_name_tool -add_rpath @loader_path/../Frameworks "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}" 2>/dev/null || true

# Copy resources
if [[ -d "${RESOURCE_BUNDLE}" ]]; then
  cp -R "${RESOURCE_BUNDLE}"/* "${APP_DIR}/Contents/Resources/"
fi

# Copy frameworks (Sparkle, Sentry)
mkdir -p "${APP_DIR}/Contents/Frameworks"
for fw in Sparkle Sentry; do
  FW_PATH="${PRODUCT_DIR}/${fw}.framework"
  if [[ -d "${FW_PATH}" ]]; then
    cp -R "${FW_PATH}" "${APP_DIR}/Contents/Frameworks/"
    echo "📦 Bundled ${fw}.framework"
  fi
done

# Create AppIcon.icns from iconset
echo "🎨 Preparing AppIcon.icns..."
cp -R "${ROOT_DIR}/Sources/SlayNodeMenuBar/Resources/AppIcon.iconset" "${APP_DIR}/Contents/Resources/"
ICONSET_PATH="${APP_DIR}/Contents/Resources/AppIcon.iconset"
if [[ -d "${ICONSET_PATH}" ]]; then
  iconutil -c icns "${ICONSET_PATH}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
  if [[ -f "${APP_DIR}/Contents/Resources/AppIcon.icns" ]]; then
    echo "✅ AppIcon.icns created successfully"
  else
    echo "❌ Failed to create AppIcon.icns"
  fi
else
  echo "❌ AppIcon.iconset missing; cannot generate icns" >&2
fi

# Code sign frameworks first, then the app
echo "🔐 Code signing app..."
for fw in "${APP_DIR}"/Contents/Frameworks/*.framework; do
  if [[ -d "${fw}" ]]; then
    codesign --force --sign - "${fw}"
  fi
done

ENTITLEMENTS_PATH="${ROOT_DIR}/SlayNode.entitlements"
if [[ -f "${ENTITLEMENTS_PATH}" ]]; then
    codesign --force --sign - --entitlements "${ENTITLEMENTS_PATH}" "${APP_DIR}"
else
    codesign --force --sign - "${APP_DIR}"
fi

echo "✅ ${APP_NAME}.app is ready at: ${APP_DIR}"
echo "🚀 Run with: open '${APP_DIR}'"
