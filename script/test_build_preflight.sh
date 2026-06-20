#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/slaynode-build-preflight-test.XXXXXX")"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

copy_repo_fixture() {
  local repo="${TEST_ROOT}/repo"
  mkdir -p "${repo}"
  cp -R \
    "${ROOT_DIR}/Sources" \
    "${ROOT_DIR}/XcodeSupport" \
    "${repo}/"
  cp \
    "${ROOT_DIR}/build.sh" \
    "${ROOT_DIR}/SlayNode.entitlements" \
    "${ROOT_DIR}/icon-iOS-Default-1024x1024@1x.png" \
    "${repo}/"

  echo "${repo}"
}

run_verify_only() {
  local repo="$1"
  shift

  (
    cd "${repo}"
    "$@" ./build.sh --verify-only
  )
}

repo="$(copy_repo_fixture)"

help_output="$(
  cd "${repo}"
  ./build.sh --help
)"
assert_contains "${help_output}" "usage: ./build.sh [debug|release] [--generate-icons] [--verify-only]"
assert_contains "${help_output}" "--verify-only"

if output="$(
  cd "${repo}"
  ./build.sh debug release 2>&1
)"; then
  fail "expected multiple build configurations to fail"
fi
assert_contains "${output}" "Multiple build configurations provided"

if output="$(run_verify_only "${repo}" env SLAYNODE_VERSION=invalid 2>&1)"; then
  fail "expected invalid SLAYNODE_VERSION to fail build preflight"
fi
assert_contains "${output}" "Invalid SLAYNODE_VERSION value"

if output="$(run_verify_only "${repo}" env SLAYNODE_BUILD_NUMBER=abc 2>&1)"; then
  fail "expected invalid SLAYNODE_BUILD_NUMBER to fail build preflight"
fi
assert_contains "${output}" "Invalid SLAYNODE_BUILD_NUMBER value"

python3 - <<'PY' "${repo}/XcodeSupport/Info.plist"
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace("<string>26.0</string>", "<string>bogus</string>"))
PY

if output="$(run_verify_only "${repo}" 2>&1)"; then
  fail "expected invalid LSMinimumSystemVersion to fail build preflight"
fi
assert_contains "${output}" "Invalid LSMinimumSystemVersion"

repo="$(copy_repo_fixture)"

if output="$(run_verify_only "${repo}" env SLAYNODE_SPARKLE_FEED_URL=https://example.test/appcast.xml 2>&1)"; then
  fail "expected missing Sparkle public key pairing to fail build preflight"
fi
assert_contains "${output}" "must both be set or both be empty"

if output="$(run_verify_only "${repo}" env \
  SLAYNODE_SPARKLE_FEED_URL=http://example.test/appcast.xml \
  SLAYNODE_SPARKLE_PUBLIC_ED_KEY=feedkey== 2>&1)"; then
  fail "expected non-https Sparkle feed URL to fail build preflight"
fi
assert_contains "${output}" "Invalid SLAYNODE_SPARKLE_FEED_URL value"

if output="$(run_verify_only "${repo}" env \
  SLAYNODE_SPARKLE_FEED_URL=https://example.test/appcast.xml \
  SLAYNODE_SPARKLE_PUBLIC_ED_KEY='bad key' 2>&1)"; then
  fail "expected Sparkle public key with whitespace to fail build preflight"
fi
assert_contains "${output}" "Invalid SLAYNODE_SPARKLE_PUBLIC_ED_KEY value"

output="$(run_verify_only "${repo}" env \
  SLAYNODE_VERSION=1.2.3 \
  SLAYNODE_BUILD_NUMBER=456 \
  SLAYNODE_SPARKLE_FEED_URL=https://example.test/appcast.xml \
  SLAYNODE_SPARKLE_PUBLIC_ED_KEY=ZmFrZS1mZWVkLWtleQ==)"
assert_contains "${output}" "Preflight OK"
assert_contains "${output}" "Version: 1.2.3"
assert_contains "${output}" "Build: 456"
assert_contains "${output}" "Minimum macOS: 26.0"
assert_contains "${output}" "Sparkle metadata: configured"

mkdir -p "${repo}/bin"
cat > "${repo}/bin/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"--show-bin-path"* ]]; then
  printf '%s\n' "$(pwd)/.build/debug"
  exit 0
fi

if [[ "$1" == "build" ]]; then
  mkdir -p .build/debug/SlayNodeMenuBar_SlayNodeMenuBar.bundle
  touch .build/debug/SlayNodeMenuBar_SlayNodeMenuBar.bundle/placeholder
  printf '#!/usr/bin/env bash\n' > .build/debug/SlayNodeMenuBar
  chmod +x .build/debug/SlayNodeMenuBar
  exit 0
fi

exit 0
EOF
chmod +x "${repo}/bin/swift"

cat > "${repo}/bin/iconutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    shift
    touch "$1"
    exit 0
  fi
  shift
done
exit 1
EOF
chmod +x "${repo}/bin/iconutil"

for command_name in codesign install_name_tool; do
  cat > "${repo}/bin/${command_name}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${repo}/bin/${command_name}"
done

output="$(
  cd "${repo}"
  PATH="${repo}/bin:$PATH" \
    SLAYNODE_SPARKLE_FEED_URL='https://example.test/appcast.xml?channel=beta&lang=en' \
    SLAYNODE_SPARKLE_PUBLIC_ED_KEY=ZmFrZS1mZWVkLWtleQ== \
    ./build.sh debug
)"
assert_contains "${output}" "SlayNode.app is ready"
plutil -lint "${repo}/SlayNode.app/Contents/Info.plist" >/dev/null

echo "PASS: build_preflight"
