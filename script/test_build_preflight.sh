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

if output="$(run_verify_only "${repo}" env SLAYNODE_VERSION=invalid 2>&1)"; then
  fail "expected invalid SLAYNODE_VERSION to fail build preflight"
fi
assert_contains "${output}" "Invalid SLAYNODE_VERSION value"

if output="$(run_verify_only "${repo}" env SLAYNODE_BUILD_NUMBER=abc 2>&1)"; then
  fail "expected invalid SLAYNODE_BUILD_NUMBER to fail build preflight"
fi
assert_contains "${output}" "Invalid SLAYNODE_BUILD_NUMBER value"

if output="$(run_verify_only "${repo}" env SLAYNODE_SPARKLE_FEED_URL=https://example.test/appcast.xml 2>&1)"; then
  fail "expected missing Sparkle public key pairing to fail build preflight"
fi
assert_contains "${output}" "must both be set or both be empty"

output="$(run_verify_only "${repo}" env \
  SLAYNODE_VERSION=1.2.3 \
  SLAYNODE_BUILD_NUMBER=456 \
  SLAYNODE_SPARKLE_FEED_URL=https://example.test/appcast.xml \
  SLAYNODE_SPARKLE_PUBLIC_ED_KEY=feed-key)"
assert_contains "${output}" "Preflight OK"
assert_contains "${output}" "Version: 1.2.3"
assert_contains "${output}" "Build: 456"
assert_contains "${output}" "Sparkle metadata: configured"

echo "PASS: build_preflight"
