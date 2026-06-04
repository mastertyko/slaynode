#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REQUESTED_VERSION="${1:-}"

if [[ -n "${REQUESTED_VERSION}" ]]; then
  NOTES="$("${SCRIPT_DIR}/extract_release_notes.sh" "${REQUESTED_VERSION}")"
else
  NOTES="$("${SCRIPT_DIR}/extract_release_notes.sh")"
fi

has_meaningful_notes() {
  printf '%s\n' "${1}" | awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/^[[:space:]]*[-*+][[:space:]]*/, "", line)
      sub(/^[[:space:]]*[0-9]+\.[[:space:]]*/, "", line)
      if (line ~ /[^[:space:]]/) {
        found = 1
        exit
      }
    }
    END {
      exit(found ? 0 : 1)
    }
  '
}

if ! has_meaningful_notes "${NOTES}"; then
  echo "❌ Release notes are empty or only contain section headings. Update CHANGELOG.md or create commits before releasing." >&2
  exit 1
fi

printf '%s\n' "${NOTES}"
