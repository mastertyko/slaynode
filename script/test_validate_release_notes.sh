#!/bin/bash
set -euo pipefail

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/slaynode-validate-release-notes-test.XXXXXX")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

make_repo() {
  local name="$1"
  local repo="${TEST_ROOT}/${name}"
  mkdir -p "${repo}/script"
  cp "${SCRIPT_DIR}/extract_release_notes.sh" "${repo}/script/extract_release_notes.sh"
  cp "${SCRIPT_DIR}/validate_release_notes.sh" "${repo}/script/validate_release_notes.sh"
  chmod +x "${repo}/script/extract_release_notes.sh" "${repo}/script/validate_release_notes.sh"
  git -C "${repo}" init -q
  git -C "${repo}" config user.name "SlayNode Test"
  git -C "${repo}" config user.email "slaynode-test@example.com"
  printf "bootstrap\n" > "${repo}/.bootstrap"
  git -C "${repo}" add .bootstrap
  git -C "${repo}" commit -q -m "chore: bootstrap"
  echo "${repo}"
}

test_passes_through_non_empty_release_notes() {
  local repo
  repo="$(make_repo "case-valid")"

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-06-03

### Fixed
- Guard empty release notes
EOF

  local output
  output="$("${repo}/script/validate_release_notes.sh")"
  assert_contains "${output}" "Guard empty release notes"
}

test_fails_when_extracted_release_notes_are_blank() {
  local repo
  repo="$(make_repo "case-blank")"

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-06-03
EOF

  git -C "${repo}" tag v1.0.0

  local output
  if output="$("${repo}/script/validate_release_notes.sh" 2>&1)"; then
    fail "expected validate_release_notes.sh to fail for blank notes"
  fi

  assert_contains "${output}" "Release notes are empty or only contain section headings"
}

test_fails_when_release_notes_only_contain_headings() {
  local repo
  repo="$(make_repo "case-heading-only")"

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-06-03

### Added

### Fixed
EOF

  local output
  if output="$("${repo}/script/validate_release_notes.sh" 2>&1)"; then
    fail "expected validate_release_notes.sh to fail for heading-only notes"
  fi

  assert_contains "${output}" "Release notes are empty or only contain section headings"
}

test_passes_through_requested_version_notes() {
  local repo
  repo="$(make_repo "case-versioned")"

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-06-03

## [1.2.3] - 2026-06-02

### Changed
- Stable release text
EOF

  local output
  output="$("${repo}/script/validate_release_notes.sh" "1.2.3")"
  assert_contains "${output}" "Stable release text"
}

test_passes_through_git_log_fallback_notes() {
  local repo
  repo="$(make_repo "case-git-log-fallback")"

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-06-03
EOF

  printf "tag base\n" > "${repo}/tagged.txt"
  git -C "${repo}" add tagged.txt
  git -C "${repo}" commit -q -m "chore: tagged base"
  git -C "${repo}" tag v1.0.0

  printf "fresh change\n" > "${repo}/fresh-change.txt"
  git -C "${repo}" add fresh-change.txt
  git -C "${repo}" commit -q -m "fix: keep git-log fallback releasable"

  local output
  output="$("${repo}/script/validate_release_notes.sh")"
  assert_contains "${output}" "fix: keep git-log fallback releasable"
}

test_passes_through_non_empty_release_notes
test_fails_when_extracted_release_notes_are_blank
test_fails_when_release_notes_only_contain_headings
test_passes_through_requested_version_notes
test_passes_through_git_log_fallback_notes

echo "PASS: validate_release_notes"
