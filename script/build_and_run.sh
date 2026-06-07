#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SlayNode"
PROCESS_NAME="SlayNodeMenuBar"
BUNDLE_ID="se.slaynode.menubar"
APP_BUNDLE="$ROOT_DIR/${APP_NAME}.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/${PROCESS_NAME}"
KILL_STRATEGY="bundle"
BUILD_SCRIPT="${BUILD_SCRIPT:-$ROOT_DIR/build.sh}"
OPEN_BIN="${OPEN_BIN:-/usr/bin/open}"
PGREP_BIN="${PGREP_BIN:-pgrep}"
PS_BIN="${PS_BIN:-ps}"
SLEEP_BIN="${SLEEP_BIN:-sleep}"

find_running_bundle_instances() {
  local pids=()
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    local command
    command="$("$PS_BIN" -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$command" == "$APP_BINARY"* ]]; then
      pids+=("$pid")
    fi
  done < <("$PGREP_BIN" -x "$PROCESS_NAME" || true)

  printf '%s\n' "${pids[@]}"
}

kill_existing_bundle_instances() {
  local pids=()
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    pids+=("$pid")
  done < <(find_running_bundle_instances)

  if [[ ${#pids[@]} -eq 0 ]]; then
    return
  fi

  kill "${pids[@]}" >/dev/null 2>&1 || true
}

kill_existing_all_instances() {
  pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
}

kill_existing() {
  case "$KILL_STRATEGY" in
    bundle)
      kill_existing_bundle_instances
      ;;
    all)
      kill_existing_all_instances
      ;;
    none)
      ;;
    *)
      echo "❌ Internal error: unknown kill strategy '$KILL_STRATEGY'" >&2
      exit 2
      ;;
  esac
}

build_app() {
  "$BUILD_SCRIPT" debug
}

open_app() {
  "$OPEN_BIN" -n "$APP_BUNDLE"
}

verify_current_bundle_running() {
  local matches=()
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    matches+=("$pid")
  done < <(find_running_bundle_instances)

  if [[ ${#matches[@]} -gt 0 ]]; then
    echo "✅ $PROCESS_NAME is running from the current bundle"
    return 0
  fi

  echo "❌ $PROCESS_NAME did not start from the current bundle as expected" >&2
  return 1
}

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify] [--no-kill|--kill-all]" >&2
  exit "${1:-2}"
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h|help)
      usage 0
      ;;
    --no-kill)
      KILL_STRATEGY="none"
      ;;
    --kill-all)
      KILL_STRATEGY="all"
      ;;
    run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
      POSITIONAL+=("$1")
      ;;
    *)
      usage
      ;;
  esac
  shift
done

if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
  MODE="${POSITIONAL[0]}"
fi

kill_existing
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    "$SLEEP_BIN" 2
    verify_current_bundle_running
    ;;
  *)
    usage
    ;;
esac
