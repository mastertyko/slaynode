#!/bin/bash
set -euo pipefail

# Release script for SlayNode
# Builds local release artifacts that match the GitHub packaging flow

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

INFO_PLIST="${ROOT_DIR}/XcodeSupport/Info.plist"
VERSION_DEFAULT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
VERSION="${1:-${VERSION_DEFAULT}}"
APP_NAME="SlayNode"
ZIP_NAME="${APP_NAME}-v${VERSION}.zip"
DMG_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/slaynode-dmg.XXXXXX")"

cleanup() {
    rm -rf "${DMG_TEMP_DIR}"
}
trap cleanup EXIT

echo "🚀 Creating SlayNode release v${VERSION}..."

# Build the app
echo "🔨 Building release version..."
./build.sh release

# Create DMG file
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
echo "📦 Creating DMG disk image..."
if [[ -f "${DMG_NAME}" ]]; then
    rm "${DMG_NAME}"
fi

mkdir -p "${DMG_TEMP_DIR}/${APP_NAME}"
cp -R "${APP_NAME}.app" "${DMG_TEMP_DIR}/${APP_NAME}/"
ln -s /Applications "${DMG_TEMP_DIR}/Applications"

# Create DMG
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_TEMP_DIR}" -ov -format UDZO "${DMG_NAME}"

echo "✅ Release ready: ${DMG_NAME}"
echo ""
echo "📋 To publish this version through GitHub Actions:"
echo "1. Commit your changes"
echo "2. Push to main"
echo "3. CI will validate the commit"
echo "4. The release workflow will create a build-numbered GitHub release for v${VERSION}"
