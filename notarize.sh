#!/bin/bash
set -euo pipefail

# Notarization script for SlayNode
# Requires: Apple Developer account with App-Specific Password
#
# Prerequisites:
# 1. Export your Developer ID certificate from Keychain Access
# 2. Create an app-specific password at appleid.apple.com
# 3. Set environment variables or pass as arguments
#
# Usage:
#   ./notarize.sh [version]
#   
# Environment variables (or create .notarize-credentials):
#   APPLE_ID          - Your Apple ID email
#   APPLE_APP_PASSWORD - App-specific password (not your Apple ID password)
#   APPLE_TEAM_ID     - Your Apple Developer Team ID
#   SIGNING_IDENTITY  - "Developer ID Application: Your Name (TEAM_ID)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFO_PLIST="${ROOT_DIR}/XcodeSupport/Info.plist"
VERSION_DEFAULT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
VERSION="${1:-${VERSION_DEFAULT}}"
APP_NAME="SlayNode"
APP_PATH="${APP_NAME}.app"
DMG_PATH="${APP_NAME}-v${VERSION}.dmg"
ZIP_PATH="${APP_NAME}-notarize.zip"

# Load credentials from file if exists
CREDENTIALS_FILE=".notarize-credentials"
if [[ -f "$CREDENTIALS_FILE" ]]; then
    echo "📋 Loading credentials from $CREDENTIALS_FILE"
    source "$CREDENTIALS_FILE"
fi

# Validate required environment variables
validate_env() {
    local missing=()
    [[ -z "${APPLE_ID:-}" ]] && missing+=("APPLE_ID")
    [[ -z "${APPLE_APP_PASSWORD:-}" ]] && missing+=("APPLE_APP_PASSWORD")
    [[ -z "${APPLE_TEAM_ID:-}" ]] && missing+=("APPLE_TEAM_ID")
    [[ -z "${SIGNING_IDENTITY:-}" ]] && missing+=("SIGNING_IDENTITY")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "❌ Missing required environment variables:"
        printf '   - %s\n' "${missing[@]}"
        echo ""
        echo "Create a .notarize-credentials file with:"
        echo "  export APPLE_ID='your@email.com'"
        echo "  export APPLE_APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'"
        echo "  export APPLE_TEAM_ID='XXXXXXXXXX'"
        echo "  export SIGNING_IDENTITY='Developer ID Application: Your Name (TEAM_ID)'"
        exit 1
    fi
}

# Step 1: Build release
build_release() {
    echo "🔨 Building release..."
    ./build.sh release
    
    if [[ ! -d "$APP_PATH" ]]; then
        echo "❌ App bundle not found at $APP_PATH"
        exit 1
    fi
}

# Step 2: Code sign with hardened runtime
code_sign() {
    echo "🔐 Code signing with hardened runtime..."
    
    codesign --force --deep --sign "$SIGNING_IDENTITY" \
        --entitlements SlayNode.entitlements \
        --options runtime \
        --timestamp \
        "$APP_PATH"
    
    echo "✅ Code signing complete"
    
    # Verify signature
    echo "🔍 Verifying signature..."
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    spctl --assess --type exec --verbose "$APP_PATH" || true
}

# Step 3: Create ZIP for notarization
create_zip() {
    echo "📦 Creating ZIP for notarization..."
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
}

# Step 4: Submit for notarization
submit_notarization() {
    echo "🍎 Submitting to Apple for notarization..."
    echo "   This may take several minutes..."
    
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait \
        --timeout 30m
}

# Step 5: Staple the notarization ticket
staple_ticket() {
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"
    
    echo "✅ Notarization complete!"
}

# Step 6: Create DMG
create_dmg() {
    echo "💿 Creating DMG..."
    
    DMG_TEMP="dmg-contents"
    rm -rf "$DMG_TEMP" "$DMG_PATH"
    
    mkdir -p "$DMG_TEMP"
    cp -R "$APP_PATH" "$DMG_TEMP/"
    ln -s /Applications "$DMG_TEMP/Applications"
    
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_PATH"
    
    rm -rf "$DMG_TEMP"
    
    # Sign and notarize the DMG too
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
    
    echo "📎 Stapling DMG..."
    xcrun stapler staple "$DMG_PATH"
}

# Cleanup
cleanup() {
    rm -f "$ZIP_PATH"
}

# Main
main() {
    echo "🚀 SlayNode Notarization Script v${VERSION}"
    echo "==========================================="
    
    validate_env
    build_release
    code_sign
    create_zip
    submit_notarization
    staple_ticket
    create_dmg
    cleanup
    
    echo ""
    echo "==========================================="
    echo "✅ Release ready: $DMG_PATH"
    echo ""
    echo "To create a GitHub release:"
    echo "  gh release create v${VERSION} '$DMG_PATH' --title 'v${VERSION}' --notes 'Release notes here'"
}

main "$@"
