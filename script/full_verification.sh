#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "==> Checking shell script syntax"
bash -n \
  build.sh \
  release.sh \
  notarize.sh \
  test-servers.sh \
  debug-port-detection.sh \
  script/build_and_run.sh \
  script/static-safety-check.sh \
  script/extract_release_notes.sh \
  script/validate_release_notes.sh \
  script/test_build_and_run.sh \
  script/test_extract_release_notes.sh \
  script/test_validate_release_notes.sh

echo "==> Running static safety checks"
./script/static-safety-check.sh

echo "==> Linting plist and entitlements"
plutil -lint XcodeSupport/Info.plist SlayNode.entitlements >/dev/null

echo "==> Checking git diff whitespace"
git diff --check -- . ':(exclude)Package.resolved'

echo "==> Verifying release note scripts"
bash script/test_build_and_run.sh
bash script/test_extract_release_notes.sh
bash script/test_validate_release_notes.sh

echo "==> Verifying debug port detection samples"
./debug-port-detection.sh --samples-only

echo "==> Running Swift test suite"
swift test --disable-sandbox
