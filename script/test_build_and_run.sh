#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/script/build_and_run.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

make_stub_suite() {
  local suite_dir="$1"
  local pgrep_output="$2"
  local other_command="$3"
  local bundle_command="$4"

  mkdir -p "$suite_dir"

  cat >"$suite_dir/pgrep" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$pgrep_output"
EOF
  chmod +x "$suite_dir/pgrep"

  cat >"$suite_dir/ps" <<EOF
#!/usr/bin/env bash
if [[ "\$1" != "-p" || "\$3" != "-o" ]]; then
  exit 2
fi
case "\$2" in
  111) printf '%s\n' "$other_command" ;;
  222) printf '%s\n' "$bundle_command" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$suite_dir/ps"
}

run_verify() {
  local suite_dir="$1"
  PATH="$suite_dir:$PATH" \
    BUILD_SCRIPT=/usr/bin/true \
    OPEN_BIN=/usr/bin/true \
    SLEEP_BIN=/usr/bin/true \
    PGREP_BIN=pgrep \
    PS_BIN=ps \
    "$SCRIPT_PATH" --verify
}

CURRENT_BUNDLE_COMMAND="$ROOT_DIR/SlayNode.app/Contents/MacOS/SlayNodeMenuBar --launched-by-test"
OTHER_BUNDLE_COMMAND="/tmp/other/SlayNode.app/Contents/MacOS/SlayNodeMenuBar --other-clone"

make_stub_suite "$TMP_DIR/fail" "111" "$OTHER_BUNDLE_COMMAND" "$CURRENT_BUNDLE_COMMAND"
if run_verify "$TMP_DIR/fail" >/dev/null 2>&1; then
  echo "FAIL: verify accepted an unrelated SlayNode bundle" >&2
  exit 1
fi

make_stub_suite "$TMP_DIR/pass" $'111\n222' "$OTHER_BUNDLE_COMMAND" "$CURRENT_BUNDLE_COMMAND"
run_verify "$TMP_DIR/pass" >/dev/null

echo "PASS: build_and_run verify scopes process checks to the current bundle"
