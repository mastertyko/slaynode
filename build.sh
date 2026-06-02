#!/bin/bash
set -euo pipefail

# Build script for SlayNodeMenuBar
# Creates a .app bundle in the project root

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"
APP_NAME="SlayNode"
APP_DIR="${ROOT_DIR}/${APP_NAME}.app"
EXECUTABLE_NAME="SlayNodeMenuBar"
CONFIGURATION="debug"
GENERATE_ICONS=false
VERIFY_ONLY=false
INFO_PLIST_TEMPLATE="${ROOT_DIR}/XcodeSupport/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
CONFIGURATION_SET=false

require_cmd() {
  local command_name="$1"

  if [[ "$command_name" == */* ]]; then
    if [[ ! -x "$command_name" ]]; then
      echo "❌ Missing executable: ${command_name}" >&2
      exit 1
    fi
    return
  fi

  command -v "$command_name" >/dev/null 2>&1 || {
    echo "❌ Missing command: ${command_name}" >&2
    exit 1
  }
}

run_preflight() {
  local required_commands=(
    swift
    codesign
    iconutil
    install_name_tool
    "${PLIST_BUDDY}"
  )

  for required in "${required_commands[@]}"; do
    require_cmd "$required"
  done
}

usage() {
  cat <<EOF
usage: $0 [debug|release] [--generate-icons]

Options:
  --generate-icons  Refresh tracked PNG assets from generate-icons.swift before building.
  --verify-only     Run preflight, metadata, plist, and asset checks without building.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --generate-icons)
      GENERATE_ICONS=true
      ;;
    --verify-only)
      VERIFY_ONLY=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "❌ Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "${CONFIGURATION_SET}" == "true" ]]; then
        echo "❌ Multiple build configurations provided: '${CONFIGURATION}' and '$1'" >&2
        usage >&2
        exit 2
      fi
      CONFIGURATION="$1"
      CONFIGURATION_SET=true
      ;;
  esac
  shift
done

CONFIGURATION="$(printf '%s' "${CONFIGURATION}" | tr '[:upper:]' '[:lower:]')"
case "${CONFIGURATION}" in
  debug|release)
    ;;
  *)
    echo "❌ Invalid configuration: '${CONFIGURATION}' (expected 'debug' or 'release')." >&2
    usage >&2
    exit 2
    ;;
esac

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

run_preflight

verify_brand_assets() {
  local missing=()
  local required_assets=(
    "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/icon_16x16.png"
    "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/icon_16x16@2x.png"
    "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/icon_32x32.png"
    "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/icon_32x32@2x.png"
    "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/icon_128x128.png"
    "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/icon_128x128@2x.png"
    "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/icon_256x256.png"
    "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/icon_256x256@2x.png"
    "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/icon_512x512.png"
    "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/icon_512x512@2x.png"
    "Sources/SlayNodeMenuBar/Resources/MenuBarIcon.png"
    "Sources/SlayNodeMenuBar/Resources/SlayNodeIcon.png"
    "Sources/SlayNodeMenuBar/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png"
    "Sources/SlayNodeMenuBar/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png"
    "icon-iOS-Default-1024x1024@1x.png"
  )

  for asset in "${required_assets[@]}"; do
    if [[ ! -f "${ROOT_DIR}/${asset}" ]]; then
      missing+=("${asset}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "❌ Missing brand assets:" >&2
    printf '   %s\n' "${missing[@]}" >&2
    echo "Run './build.sh --generate-icons' to recreate them." >&2
    exit 1
  fi
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "${value}"
}

APP_VERSION_DEFAULT="$("${PLIST_BUDDY}" -c 'Print :CFBundleShortVersionString' "${INFO_PLIST_TEMPLATE}")"
APP_BUILD_DEFAULT="$("${PLIST_BUDDY}" -c 'Print :CFBundleVersion' "${INFO_PLIST_TEMPLATE}")"
MIN_SYSTEM_VERSION="$("${PLIST_BUDDY}" -c 'Print :LSMinimumSystemVersion' "${INFO_PLIST_TEMPLATE}")"

APP_VERSION="${SLAYNODE_VERSION:-${APP_VERSION_DEFAULT}}"
APP_BUILD="${SLAYNODE_BUILD_NUMBER:-${APP_BUILD_DEFAULT}}"
SPARKLE_FEED_URL="${SLAYNODE_SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SLAYNODE_SPARKLE_PUBLIC_ED_KEY:-}"

validate_bundle_metadata() {
  local version="$1"
  local build="$2"

  if [[ ! "${version}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "❌ Invalid SLAYNODE_VERSION value: '${version}' (expected numeric SemVer-like form, e.g. 1.0.0)." >&2
    exit 2
  fi

  if [[ ! "${build}" =~ ^[0-9]+$ ]]; then
    echo "❌ Invalid SLAYNODE_BUILD_NUMBER value: '${build}' (expected an integer)." >&2
    exit 2
  fi
}

validate_sparkle_pairing() {
  local has_feed=false
  local has_key=false
  [[ -n "${SPARKLE_FEED_URL}" ]] && has_feed=true
  [[ -n "${SPARKLE_PUBLIC_ED_KEY}" ]] && has_key=true

  if [[ "${has_feed}" != "${has_key}" ]]; then
    echo "❌ SLAYNODE_SPARKLE_FEED_URL and SLAYNODE_SPARKLE_PUBLIC_ED_KEY must both be set or both be empty." >&2
    exit 2
  fi
}

validate_bundle_metadata "${APP_VERSION}" "${APP_BUILD}"
validate_sparkle_pairing

run_verify_only_checks() {
  echo "🔎 Running SlayNode build preflight..."
  verify_brand_assets
  plutil -lint "${INFO_PLIST_TEMPLATE}" "${ROOT_DIR}/SlayNode.entitlements" >/dev/null
  echo "✅ Preflight OK"
  echo "   Configuration: ${CONFIGURATION}"
  echo "   Version: ${APP_VERSION}"
  echo "   Build: ${APP_BUILD}"
  if [[ -n "${SPARKLE_FEED_URL}" ]]; then
    echo "   Sparkle metadata: configured"
  else
    echo "   Sparkle metadata: not configured"
  fi
}

if [[ "${VERIFY_ONLY}" == "true" ]]; then
  run_verify_only_checks
  exit 0
fi

SPARKLE_INFO=""
if [[ -n "${SPARKLE_FEED_URL}" && -n "${SPARKLE_PUBLIC_ED_KEY}" ]]; then
  SPARKLE_FEED_URL_XML="$(xml_escape "${SPARKLE_FEED_URL}")"
  SPARKLE_PUBLIC_ED_KEY_XML="$(xml_escape "${SPARKLE_PUBLIC_ED_KEY}")"
  SPARKLE_INFO=$(cat <<EOF
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL_XML}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_ED_KEY_XML}</string>
EOF
)
fi

echo "🔨 Building SlayNodeMenuBar (${CONFIGURATION})..."
if [[ "${GENERATE_ICONS}" == "true" ]]; then
  echo "🎨 Regenerating brand assets..."
  swift generate-icons.swift
else
  echo "🎨 Using checked-in brand assets (pass --generate-icons to refresh them)..."
fi
verify_brand_assets
swift build -c "${CONFIGURATION}"

PRODUCT_DIR="$(swift build --show-bin-path -c "${CONFIGURATION}")"
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
    <string>se.slaynode.menubar</string>
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
