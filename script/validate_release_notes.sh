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

if ! printf '%s\n' "${NOTES}" | grep -q '[^[:space:]]'; then
  echo "❌ Release notes are empty. Update CHANGELOG.md or create commits before releasing." >&2
  exit 1
fi

printf '%s\n' "${NOTES}"
