#!/bin/bash
set -euo pipefail

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/slaynode-release-notes-test.XXXXXX")"
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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "did not expect output to contain '${needle}'"
  fi
}

make_repo() {
  local name="$1"
  local repo="${TEST_ROOT}/${name}"
  mkdir -p "${repo}/script"
  cp "${SCRIPT_DIR}/extract_release_notes.sh" "${repo}/script/extract_release_notes.sh"
  chmod +x "${repo}/script/extract_release_notes.sh"
  git -C "${repo}" init -q
  git -C "${repo}" config user.name "SlayNode Test"
  git -C "${repo}" config user.email "slaynode-test@example.com"
  printf "bootstrap\n" > "${repo}/.bootstrap"
  git -C "${repo}" add .bootstrap
  git -C "${repo}" commit -q -m "chore: bootstrap"
  echo "${repo}"
}

test_prefers_unreleased_section() {
  local repo
  repo="$(make_repo "case-unreleased")"

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-05-31

### Added
- Fresh note from unreleased section

## [1.0.0] - 2026-01-01

### Added
- Old release note
EOF

  local output
  output="$("${repo}/script/extract_release_notes.sh")"
  assert_contains "${output}" "Fresh note from unreleased section"
  assert_not_contains "${output}" "Old release note"
}

test_uses_requested_version_when_unreleased_is_empty() {
  local repo
  repo="$(make_repo "case-requested-version")"

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-05-31

## [1.2.3] - 2026-05-30

### Fixed
- Patched release line
EOF

  local output
  output="$("${repo}/script/extract_release_notes.sh" "1.2.3")"
  assert_contains "${output}" "Patched release line"
}

test_falls_back_to_git_log_since_previous_tag() {
  local repo
  repo="$(make_repo "case-previous-tag")"

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-05-31
EOF

  printf "tag\n" > "${repo}/tagged.txt"
  git -C "${repo}" add tagged.txt
  git -C "${repo}" commit -q -m "chore: tagged base"
  git -C "${repo}" tag v1.0.0

  printf "new feature\n" > "${repo}/feature.txt"
  git -C "${repo}" add feature.txt
  git -C "${repo}" commit -q -m "feat: add git-log fallback note"

  local output
  output="$("${repo}/script/extract_release_notes.sh")"
  assert_contains "${output}" "- feat: add git-log fallback note"
}

test_falls_back_to_git_log_when_requested_version_is_missing() {
  local repo
  repo="$(make_repo "case-missing-requested-version")"

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-05-31

## [1.2.0] - 2026-05-30

### Changed
- Previous release entry
EOF

  printf "tag base\n" > "${repo}/tagged.txt"
  git -C "${repo}" add tagged.txt
  git -C "${repo}" commit -q -m "chore: tagged base"
  git -C "${repo}" tag v1.2.0

  printf "new fallback entry\n" > "${repo}/fallback.txt"
  git -C "${repo}" add fallback.txt
  git -C "${repo}" commit -q -m "fix: fallback when requested version is missing"

  local output
  output="$("${repo}/script/extract_release_notes.sh" "9.9.9")"
  assert_contains "${output}" "- fix: fallback when requested version is missing"
}

test_no_tag_fallback_is_limited_to_recent_commits() {
  local repo
  repo="$(make_repo "case-no-tag-limit")"

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased] - 2026-05-31
EOF

  for index in $(seq 1 12); do
    printf "entry %s\n" "${index}" > "${repo}/entry-${index}.txt"
    git -C "${repo}" add "entry-${index}.txt"
    git -C "${repo}" commit -q -m "chore: log fallback ${index}"
  done

  local output
  output="$("${repo}/script/extract_release_notes.sh")"
  assert_contains "${output}" "- chore: log fallback 12"
  assert_not_contains "${output}" "- chore: log fallback 2"
}

test_prefers_unreleased_section
test_uses_requested_version_when_unreleased_is_empty
test_falls_back_to_git_log_since_previous_tag
test_falls_back_to_git_log_when_requested_version_is_missing
test_no_tag_fallback_is_limited_to_recent_commits

echo "PASS: extract_release_notes"
