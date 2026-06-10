#!/bin/bash
set -euo pipefail

# Release script for SlayNode
# Builds local release artifacts that match the GitHub packaging flow

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

usage() {
    cat <<USAGE
usage: ./release.sh [version] [--build-number <number>]

Examples:
  ./release.sh
  ./release.sh 1.0.3
  ./release.sh 1.0.3 --build-number 150
USAGE
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "❌ Missing command: $1" >&2
        exit 1
    }
}

VERSION_ARGUMENT=""
BUILD_NUMBER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --build-number)
            if [[ $# -lt 2 ]]; then
                echo "❌ Missing value for --build-number." >&2
                usage >&2
                exit 2
            fi
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --*)
            echo "❌ Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [[ -n "${VERSION_ARGUMENT}" ]]; then
                echo "❌ Too many positional arguments." >&2
                usage >&2
                exit 2
            fi
            VERSION_ARGUMENT="$1"
            shift
            ;;
    esac
done

for cmd in swift ditto hdiutil /usr/libexec/PlistBuddy; do
    require_cmd "$cmd"
done

INFO_PLIST="${ROOT_DIR}/XcodeSupport/Info.plist"
VERSION_DEFAULT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
VERSION="${VERSION_ARGUMENT:-${VERSION_DEFAULT}}"

if ! [[ "${VERSION}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "❌ Invalid version: ${VERSION}" >&2
    exit 2
fi

if [[ -n "${BUILD_NUMBER}" && ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
    echo "❌ Invalid build number: ${BUILD_NUMBER}" >&2
    exit 2
fi

APP_NAME="SlayNode"
ARTIFACT_SUFFIX="-v${VERSION}"
if [[ -n "${BUILD_NUMBER}" ]]; then
    ARTIFACT_SUFFIX="${ARTIFACT_SUFFIX}-build.${BUILD_NUMBER}"
fi
ZIP_NAME="${APP_NAME}${ARTIFACT_SUFFIX}.zip"
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
if [[ -n "${BUILD_NUMBER}" ]]; then
    SLAYNODE_VERSION="${VERSION}" SLAYNODE_BUILD_NUMBER="${BUILD_NUMBER}" ./build.sh release
else
    SLAYNODE_VERSION="${VERSION}" ./build.sh release
fi

if [[ -f "${ZIP_NAME}" ]]; then
    rm "${ZIP_NAME}"
fi

echo "📦 Creating ZIP archive..."
ditto -c -k --keepParent "${APP_NAME}.app" "${ZIP_NAME}"

# Create DMG file
DMG_NAME="${APP_NAME}${ARTIFACT_SUFFIX}.dmg"
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
if [[ -n "${BUILD_NUMBER}" ]]; then
    echo "✅ Build number: ${BUILD_NUMBER}"
fi
echo ""
echo "📋 To publish this version through GitHub Actions:"
echo "1. Commit your changes"
echo "2. Push to main"
echo "3. CI will validate the commit"
echo "4. The release workflow will create a build-numbered GitHub release for v${VERSION}"
