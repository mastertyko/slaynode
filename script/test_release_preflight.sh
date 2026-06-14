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

REPO_VERIFY="${TEST_ROOT}/repo-verify"
mkdir -p "${REPO_VERIFY}/script" "${REPO_VERIFY}/XcodeSupport"
cp "${ROOT_DIR}/release.sh" "${REPO_VERIFY}/release.sh"
cp "${ROOT_DIR}/script/extract_release_notes.sh" "${REPO_VERIFY}/script/extract_release_notes.sh"
cp "${ROOT_DIR}/script/validate_release_notes.sh" "${REPO_VERIFY}/script/validate_release_notes.sh"
chmod +x "${REPO_VERIFY}/release.sh" "${REPO_VERIFY}/script/extract_release_notes.sh" "${REPO_VERIFY}/script/validate_release_notes.sh"

cat > "${REPO_VERIFY}/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> build-invocations.log
if [[ "$1" == "--verify-only" ]]; then
  echo "preflight failed" >&2
  exit 42
fi
echo "release build should not run" >&2
exit 99
EOF
chmod +x "${REPO_VERIFY}/build.sh"

cat > "${REPO_VERIFY}/XcodeSupport/Info.plist" <<'EOF'
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

cat > "${REPO_VERIFY}/CHANGELOG.md" <<'EOF'
# Changelog

## [1.2.3] - 2026-06-14

### Fixed
- Verified release build preflight runs first
EOF

git -C "${REPO_VERIFY}" init -q
git -C "${REPO_VERIFY}" config user.name "SlayNode Test"
git -C "${REPO_VERIFY}" config user.email "slaynode-test@example.com"
touch "${REPO_VERIFY}/.bootstrap"
git -C "${REPO_VERIFY}" add .
git -C "${REPO_VERIFY}" commit -q -m "chore: bootstrap"

if output="$(cd "${REPO_VERIFY}" && ./release.sh 1.2.3 2>&1)"; then
  fail "expected release.sh to stop when build preflight fails"
fi

assert_contains "${output}" "preflight failed"
assert_contains "$(cat "${REPO_VERIFY}/build-invocations.log")" "--verify-only"
if grep -Fxq "release" "${REPO_VERIFY}/build-invocations.log"; then
  fail "did not expect release build to run after preflight failure"
fi

echo "PASS: release_preflight"
