#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SlayNode"
PROCESS_NAME="SlayNodeMenuBar"
BUNDLE_ID="com.slaynode.menubar"
APP_BUNDLE="$ROOT_DIR/${APP_NAME}.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/${PROCESS_NAME}"

kill_existing() {
  pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
}

build_app() {
  "$ROOT_DIR/build.sh" debug
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
  exit 2
}

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
    pgrep -x "$PROCESS_NAME" >/dev/null
    ;;
  *)
    usage
    ;;
esac
