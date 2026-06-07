#!/bin/bash
set -euo pipefail

# Release script for SlayNode
# Builds local release artifacts that match the GitHub packaging flow

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

usage() {
    cat <<USAGE
usage: ./release.sh [version]

Examples:
  ./release.sh
  ./release.sh 1.0.3
USAGE
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "❌ Missing command: $1" >&2
        exit 1
    }
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 1 ]]; then
    echo "❌ Too many arguments." >&2
    usage >&2
    exit 2
fi

for cmd in swift ditto hdiutil /usr/libexec/PlistBuddy; do
    require_cmd "$cmd"
done

INFO_PLIST="${ROOT_DIR}/XcodeSupport/Info.plist"
VERSION_DEFAULT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
VERSION="${1:-${VERSION_DEFAULT}}"

if ! [[ "${VERSION}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "❌ Invalid version: ${VERSION}" >&2
    exit 2
fi

APP_NAME="SlayNode"
ZIP_NAME="${APP_NAME}-v${VERSION}.zip"
DMG_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/slaynode-dmg.XXXXXX")"

cleanup() {
    rm -rf "${DMG_TEMP_DIR}"
}
trap cleanup EXIT

echo "🚀 Creating SlayNode release v${VERSION}..."

echo "📝 Validating release notes..."
"${ROOT_DIR}/script/validate_release_notes.sh" "${VERSION}" >/dev/null

# Build the app
echo "🔨 Building release version..."
SLAYNODE_VERSION="${VERSION}" ./build.sh release

if [[ -f "${ZIP_NAME}" ]]; then
    rm "${ZIP_NAME}"
fi

echo "📦 Creating ZIP archive..."
ditto -c -k --keepParent "${APP_NAME}.app" "${ZIP_NAME}"

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
echo "✅ Release ready: ${ZIP_NAME}"
echo ""
echo "📋 To publish this version through GitHub Actions:"
echo "1. Commit your changes"
echo "2. Push to main"
echo "3. CI will validate the commit"
echo "4. The release workflow will create a build-numbered GitHub release for v${VERSION}"
