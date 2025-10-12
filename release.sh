#!/bin/bash
set -euo pipefail

# Release script for SlayNode
# Builds and creates GitHub releases

VERSION="${1:-1.2.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Slaynode"
ZIP_NAME="${APP_NAME}-v${VERSION}.app.zip"

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

# Create temporary directory for DMG contents
DMG_TEMP_DIR="dmg-draft"
mkdir -p "${DMG_TEMP_DIR}/${APP_NAME}"
cp -R "${APP_NAME}.app" "${DMG_TEMP_DIR}/${APP_NAME}/"
ln -s /Applications "${DMG_TEMP_DIR}/Applications"

# Create DMG
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_TEMP_DIR}" -ov -format UDZO "${DMG_NAME}"

# Clean up
rm -rf "${DMG_TEMP_DIR}"

echo "✅ Release ready: ${DMG_NAME}"
echo ""
echo "📋 To complete the release:"
echo "1. Push your changes: git push origin main"
echo "2. Create GitHub release: gh release create v${VERSION}"
echo "3. Upload DMG file: gh release upload v${VERSION} ${DMG_NAME}"
echo ""
echo "Or use the automated commands:"
echo "git add . && git commit -m 'build: Update build.sh to version ${VERSION}' && git push"
echo "gh release create v${VERSION} --title 'v${VERSION}: Release Notes' --notes 'Release description here'"
echo "gh release upload v${VERSION} ${DMG_NAME}"