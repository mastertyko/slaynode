#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/slaynode-release-preflight-test.XXXXXX")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain '${needle}'"
  fi
}

REPO="${TEST_ROOT}/repo"
mkdir -p "${REPO}/script" "${REPO}/XcodeSupport"
cp "${ROOT_DIR}/release.sh" "${REPO}/release.sh"
cp "${ROOT_DIR}/script/extract_release_notes.sh" "${REPO}/script/extract_release_notes.sh"
cp "${ROOT_DIR}/script/validate_release_notes.sh" "${REPO}/script/validate_release_notes.sh"
chmod +x "${REPO}/release.sh" "${REPO}/script/extract_release_notes.sh" "${REPO}/script/validate_release_notes.sh"

cat > "${REPO}/build.sh" <<'EOF'
#!/usr/bin/env bash
echo "build should not run" >&2
exit 99
EOF
chmod +x "${REPO}/build.sh"

cat > "${REPO}/XcodeSupport/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>1.2.3</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
</dict>
</plist>
EOF

cat > "${REPO}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-06-07

### Fixed
EOF

git -C "${REPO}" init -q
git -C "${REPO}" config user.name "SlayNode Test"
git -C "${REPO}" config user.email "slaynode-test@example.com"
touch "${REPO}/.bootstrap"
git -C "${REPO}" add .
git -C "${REPO}" commit -q -m "chore: bootstrap"

if output="$("${REPO}/release.sh" 1.2.3 2>&1)"; then
  fail "expected release.sh to fail before build when release notes are blank"
fi

assert_contains "${output}" "Release notes are empty or only contain section headings"

echo "PASS: release_preflight"
