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

kill_existing_bundle_instances() {
  local pids=()
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    local command
    command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$command" == "$APP_BINARY"* ]]; then
      pids+=("$pid")
    fi
  done < <(pgrep -x "$PROCESS_NAME" || true)

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
  "$ROOT_DIR/build.sh" debug
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
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
    sleep 2
    if pgrep -x "$PROCESS_NAME" >/dev/null; then
      echo "✅ $PROCESS_NAME is running"
    else
      echo "❌ $PROCESS_NAME did not start as expected" >&2
      exit 1
    fi
    ;;
  *)
    usage
    ;;
esac
