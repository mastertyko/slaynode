#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG_PATH="${ROOT_DIR}/CHANGELOG.md"
REQUESTED_VERSION=""
PRINT_SOURCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-source)
      PRINT_SOURCE=true
      ;;
    -h|--help)
      cat <<'EOF'
usage: ./script/extract_release_notes.sh [version] [--print-source]

Outputs the chosen release note body by default.
Pass --print-source to output only one of: unreleased, versioned, git-log.
EOF
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [[ -n "${REQUESTED_VERSION}" ]]; then
        echo "Too many positional arguments." >&2
        exit 2
      fi
      REQUESTED_VERSION="$1"
      ;;
  esac
  shift
done

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

emit_notes() {
  local source="$1"
  local notes="$2"

  if [[ "${PRINT_SOURCE}" == "true" ]]; then
    printf '%s\n' "${source}"
  else
    printf '%s\n' "${notes}"
  fi
}

UNRELEASED_CONTENT="$(extract_section '## [Unreleased]' | trim_blank_edges)"

if printf '%s\n' "${UNRELEASED_CONTENT}" | grep -q '[^[:space:]]'; then
  emit_notes "unreleased" "${UNRELEASED_CONTENT}"
  exit 0
fi

if [[ -n "${REQUESTED_VERSION}" ]]; then
  VERSION_CONTENT="$(extract_section "## [${REQUESTED_VERSION}]" | trim_blank_edges)"

  if printf '%s\n' "${VERSION_CONTENT}" | grep -q '[^[:space:]]'; then
    emit_notes "versioned" "${VERSION_CONTENT}"
    exit 0
  fi
fi

PREVIOUS_TAG="$(git -C "${ROOT_DIR}" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"

if [[ -n "${PREVIOUS_TAG}" ]]; then
  GIT_LOG_NOTES="$(git -C "${ROOT_DIR}" log --pretty='- %s' "${PREVIOUS_TAG}..HEAD")"
else
  GIT_LOG_NOTES="$(git -C "${ROOT_DIR}" log --pretty='- %s' -n 10)"
fi

emit_notes "git-log" "${GIT_LOG_NOTES}"
