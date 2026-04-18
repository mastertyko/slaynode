#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG_PATH="${ROOT_DIR}/CHANGELOG.md"
REQUESTED_VERSION="${1:-}"

if [[ ! -f "${CHANGELOG_PATH}" ]]; then
  echo "CHANGELOG.md not found at ${CHANGELOG_PATH}" >&2
  exit 1
fi

extract_section() {
  local heading_prefix="$1"

  awk -v heading_prefix="${heading_prefix}" '
    $0 ~ /^## \[/ {
      if (capturing) {
        exit
      }
    }

    index($0, heading_prefix) == 1 {
      capturing = 1
      next
    }

    capturing {
      print
    }
  ' "${CHANGELOG_PATH}"
}

trim_blank_edges() {
  awk '
    { lines[NR] = $0 }
    END {
      first = 1
      while (first <= NR && lines[first] == "") {
        first++
      }

      last = NR
      while (last >= first && lines[last] == "") {
        last--
      }

      for (i = first; i <= last; i++) {
        print lines[i]
      }
    }
  '
}

UNRELEASED_CONTENT="$(extract_section '## [Unreleased]' | trim_blank_edges)"

if printf '%s\n' "${UNRELEASED_CONTENT}" | grep -q '[^[:space:]]'; then
  printf '%s\n' "${UNRELEASED_CONTENT}"
  exit 0
fi

if [[ -n "${REQUESTED_VERSION}" ]]; then
  VERSION_CONTENT="$(extract_section "## [${REQUESTED_VERSION}]" | trim_blank_edges)"

  if printf '%s\n' "${VERSION_CONTENT}" | grep -q '[^[:space:]]'; then
    printf '%s\n' "${VERSION_CONTENT}"
    exit 0
  fi
fi

PREVIOUS_TAG="$(git -C "${ROOT_DIR}" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"

if [[ -n "${PREVIOUS_TAG}" ]]; then
  git -C "${ROOT_DIR}" log --pretty='- %s' "${PREVIOUS_TAG}..HEAD"
else
  git -C "${ROOT_DIR}" log --pretty='- %s' -n 10
fi
