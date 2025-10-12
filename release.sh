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

# Create zip file
echo "📦 Creating release zip..."
if [[ -f "${ZIP_NAME}" ]]; then
    rm "${ZIP_NAME}"
fi
zip -r "${ZIP_NAME}" "${APP_NAME}.app"

echo "✅ Release ready: ${ZIP_NAME}"
echo ""
echo "📋 To complete the release:"
echo "1. Push your changes: git push origin main"
echo "2. Create GitHub release: gh release create v${VERSION}"
echo "3. Upload zip file: gh release upload v${VERSION} ${ZIP_NAME}"
echo ""
echo "Or use the automated commands:"
echo "git add . && git commit -m 'build: Update build.sh to version ${VERSION}' && git push"
echo "gh release create v${VERSION} --title 'v${VERSION}: Release Notes' --notes 'Release description here'"
echo "gh release upload v${VERSION} ${ZIP_NAME}"