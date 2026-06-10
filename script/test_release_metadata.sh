#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/slaynode-release-metadata-test.XXXXXX")"
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
chmod +x "${REPO}/release.sh"

cat > "${REPO}/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p SlayNode.app
EOF
chmod +x "${REPO}/build.sh"

cat > "${REPO}/script/validate_release_notes.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "${REPO}/script/validate_release_notes.sh"

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

output="$(cd "${REPO}" && PATH="${REPO}:$PATH" ./release.sh 1.2.3 --build-number 150)"
assert_contains "${output}" "Release metadata: SlayNode-v1.2.3-build.150-release-metadata.json"

python3 - <<'PY' "${REPO}/SlayNode-v1.2.3-build.150-release-metadata.json"
from __future__ import annotations

import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["version"] == "1.2.3"
assert payload["build_number"] == "150"
assert payload["minimum_macos"] == "26.0"
assert payload["dmg_name"] == "SlayNode-v1.2.3-build.150.dmg"
assert payload["zip_name"] == "SlayNode-v1.2.3-build.150.zip"
assert payload["source"] == "local_release"
PY

echo "PASS: release_metadata"
