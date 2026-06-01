#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

status=0

print_section() {
  printf '\n[%s]\n' "$1"
}

report_failure() {
  local title="$1"
  local findings="$2"
  printf 'FAIL: %s\n%s\n' "$title" "$findings"
  status=1
}

print_section "Unsafe Swift constructs"
unsafe_matches="$(rg -n --glob '*.swift' '\b(?:try!|as!)\b' Sources || true)"
if [ -n "$unsafe_matches" ]; then
  report_failure "Unexpected force-unwrap constructs found in Sources" "$unsafe_matches"
else
  echo "OK: no try! or as! usage in Sources"
fi

fatal_matches="$(rg -n --glob '*.swift' 'fatalError\(' Sources || true)"
if [ -n "$fatal_matches" ]; then
  # One fatalError remains intentionally as a last-resort startup guard.
  unexpected_fatal="$(printf '%s\n' "$fatal_matches" | rg -v '^Sources/SlayNodeMenuBar/SlayNodeMenuBarApp.swift:' || true)"
  if [ -n "$unexpected_fatal" ]; then
    report_failure "Unexpected fatalError usage found in Sources" "$unexpected_fatal"
  else
    echo "OK: fatalError usage limited to startup guard in SlayNodeMenuBarApp"
  fi
else
  echo "OK: no fatalError usage in Sources"
fi

print_section "Potential secret fixtures"
secret_matches="$(rg -n -i \
  --glob '*.swift' \
  --glob '*.sh' \
  --glob '*.md' \
  '(ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|authorization:\s*bearer\s+[A-Za-z0-9._-]{20,})' \
  Sources script docs || true)"

if [ -n "$secret_matches" ]; then
  report_failure "Potential unredacted secret fixture(s) found" "$secret_matches"
else
  echo "OK: no obvious secret fixtures detected in Sources/script/docs"
fi

print_section "Hardcoded local paths"
local_path_matches="$(rg -n \
  --glob '*.sh' \
  --glob '*.md' \
  --glob '*.yml' \
  --glob '*.yaml' \
  '/Users/[^/]+/(?:\\.codex|\\.config|Documents|Desktop|Downloads|Library)/' \
  script docs .github/workflows || true)"

if [ -n "$local_path_matches" ]; then
  report_failure "Hardcoded user-local absolute path(s) found" "$local_path_matches"
else
  echo "OK: no hardcoded user-local absolute paths in scripts/docs/workflows"
fi

if [ "$status" -ne 0 ]; then
  exit "$status"
fi

printf '\nAll static safety checks passed.\n'
