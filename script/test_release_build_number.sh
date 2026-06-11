#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/slaynode-release-build-number-test.XXXXXX")"
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
chmod +x "${REPO}/release.sh"
chmod +x "${REPO}/script/extract_release_notes.sh"

cat > "${REPO}/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "${SLAYNODE_VERSION:-}:${SLAYNODE_BUILD_NUMBER:-}" > build-env.txt
mkdir -p SlayNode.app
EOF
chmod +x "${REPO}/build.sh"

cat > "${REPO}/script/validate_release_notes.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "${REPO}/script/validate_release_notes.sh"

cat > "${REPO}/CHANGELOG.md" <<'EOF'
# Changelog

## [1.2.3] - 2026-06-11

### Changed
- Local build number parity
EOF

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

cat > "${REPO}/ditto" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
touch "${@: -1}"
EOF
chmod +x "${REPO}/ditto"

cat > "${REPO}/hdiutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
touch "${@: -1}"
EOF
chmod +x "${REPO}/hdiutil"

git -C "${REPO}" init -q
git -C "${REPO}" config user.name "SlayNode Test"
git -C "${REPO}" config user.email "slaynode-test@example.com"
git -C "${REPO}" add .
git -C "${REPO}" commit -q -m "chore: bootstrap"

if output="$(cd "${REPO}" && PATH="${REPO}:$PATH" ./release.sh 1.2.3 --build-number 150 2>&1)"; then
  :
else
  printf '%s\n' "${output}" >&2
  fail "release.sh failed unexpectedly with explicit build number"
fi

assert_contains "${output}" "SlayNode-v1.2.3-build.150.dmg"
assert_contains "${output}" "SlayNode-v1.2.3-build.150.zip"
assert_contains "${output}" "Build number: 150"
assert_contains "$(cat "${REPO}/build-env.txt")" "1.2.3:150"

if output="$(cd "${REPO}" && PATH="${REPO}:$PATH" ./release.sh 1.2.3 --build-number nope 2>&1)"; then
  fail "expected invalid build number to fail"
fi

assert_contains "${output}" "Invalid build number"

echo "PASS: release_build_number"
