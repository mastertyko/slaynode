#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: ./debug-port-detection.sh [--live-only|--samples-only|--command <text>]

Options:
  --live-only     Show only current process snapshot.
  --samples-only  Run only sample-command port extraction.
  --command TEXT  Run extraction for one explicit command string.
  -h, --help      Show this help text.
USAGE
}

extract_ports() {
  local command="$1"

  local extracted
  extracted=$(
    printf '%s\n' "$command" | perl -ne '
      while (/(?:^|\s)(?:[A-Za-z_][A-Za-z0-9_]*_)?PORT=(?:[\x27"]?)([0-9]{1,5})(?:[\x27"]?)(?:\D|$)/gi) { print "$1\n" }
      while (/(?:^|\s)(?:[A-Za-z_][A-Za-z0-9_]*_)?PORT=\$\{[^}:]+:-(?:[\x27"]?)([0-9]{1,5})(?:[\x27"]?)\}(?:\D|$)/gi) { print "$1\n" }
      while (/(?:^|\s)(?:[A-Za-z_][A-Za-z0-9_]*_)?PORT=\$\{[^}:]+:=(?:[\x27"]?)([0-9]{1,5})(?:[\x27"]?)\}(?:\D|$)/gi) { print "$1\n" }
      while (/(?:^|\s)(?:[A-Za-z_][A-Za-z0-9_]*_)?PORT=\$\{[^}-]+-(?:[\x27"]?)([0-9]{1,5})(?:[\x27"]?)\}(?:\D|$)/gi) { print "$1\n" }
      while (/(?:^|\s)(?:[A-Za-z_][A-Za-z0-9_]*_)?PORT=\$\{[^}=]+=(?:[\x27"]?)([0-9]{1,5})(?:[\x27"]?)\}(?:\D|$)/gi) { print "$1\n" }
      while (/(?:^|\s)-D[A-Za-z0-9_.-]*[._-]port=(?:[\x27"]?)([0-9]{1,5})(?:[\x27"]?)(?:\D|$)/gi) { print "$1\n" }
      while (/(?:^|\s)-D[A-Za-z0-9_.-]*[._-]port=(?:[^:\s]+|\[[^\]]+\]):([0-9]{1,5})(?:\D|$)/gi) { print "$1\n" }
      while (/(?:--(?:port|[A-Za-z0-9][A-Za-z0-9-]*-port)\s*=?\s*(?:[^:\s]+|\[[^\]]+\]):)([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/(?:--(?:port|[A-Za-z0-9][A-Za-z0-9-]*-port)\s*=?\s*)([0-9]{1,5})(?![.:])(?:\D|$)/g) { print "$1\n" }
      while (/(?:^|\s)-p\s*=?\s*(?:[^:\s]+|\[[^\]]+\]):([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/(?:^|\s)-p\s*=?\s*([0-9]{1,5})(?![.:])(?:\D|$)/g) { print "$1\n" }
      while (/(?:^|\s)-p([0-9]{1,5})(?![.:])(?:\D|$)/g) { print "$1\n" }
      while (/(?:--inspect-port\s*=?\s*(?:[^:\s]+|\[[^\]]+\]):)([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/(?:--inspect-port\s*=?\s*)([0-9]{1,5})(?![.:])(?:\D|$)/g) { print "$1\n" }
      while (/(?:--(?:inspect|inspect-brk|inspect-wait)\s*=?\s*)([0-9]{1,5})(?![.:])(?:\D|$)/g) { print "$1\n" }
      while (/(?:--(?:inspect|inspect-brk|inspect-wait)\s*=?\s*(?:[^:\s]+:))([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/(?:--(?:inspect|inspect-brk|inspect-wait)\s*=?\s*)(?:\[[^\]]+\]|localhost|0\.0\.0\.0|127(?:\.\d{1,3}){3}|::1)(?=[\s,;]|$)/g) { print "9229\n" }
      while (/(?:--(?:listen|listen-address|addr|address|bind|socket)\s*=?\s*(?:[^:\s]+|\[[^\]]+\]):)([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/(?:--(?:listen|listen-address|addr|address|bind|socket)\s*=?\s*)([0-9]{1,5})(?![.:])(?:\D|$)/g) { print "$1\n" }
      while (/(?:[A-Za-z][A-Za-z0-9+.-]*:\/\/\[[^\]]+\]:)([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/(?:[A-Za-z][A-Za-z0-9+.-]*:\/\/[^:\s]+:)([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/(?:^|\s)runserver\s+([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/(?:^|\s)http\.server\s+([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/(?:^|\s)http\.server(?:\s+(?:--bind|-b)\s+\S+)?(?:\s+(?:--directory|-d)\s+\S+)?(?:\s+--protocol\s+\S+)?\s+([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/(?:localhost|127(?:\.\d{1,3}){3}|0\.0\.0\.0):([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/\[[^\]]+\]:([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
      while (/\*:([0-9]{1,5})(?:\D|$)/g) { print "$1\n" }
    ' | awk '$1 >= 1 && $1 <= 65535'
  )

  if [[ -z "$extracted" ]]; then
    echo "  (inga port-träffar)"
    return
  fi

  printf '%s\n' "$extracted" | awk '!seen[$0]++' | sort -n | sed 's/^/  :/'
}

show_live_processes() {
  echo "=== Live process snapshot (Node/dev wrappers) ==="
  ps -axo pid=,command= \
    | awk '
        $0 ~ /^[[:space:]]*[0-9]+ / &&
        $0 ~ /(node|npm|pnpm|yarn|npx|bun|deno)([[:space:]]|$)/ {
          print
        }
      ' \
    | head -20 || true
}

show_samples() {
  local samples=(
    "npm run dev -- --port 3001"
    "rails server -p 3003"
    "python manage.py runserver 8000"
    "python3 -m http.server 8080"
    "python3 -m http.server --bind 127.0.0.1 --directory public 8081"
    "puma -p3004"
    "node server.js --port 8080"
    "vite --port 5173 --host 0.0.0.0"
    "PORT=4173 npm run preview"
    "web_port=5174 npm run dev"
    "PORT=\"3002\" npm run dev"
    "WEB_PORT=\${WEB_PORT:-4174} pnpm dev"
    "API_PORT=\${API_PORT:=4200} pnpm dev"
    "PUBLIC_URL=\${PUBLIC_URL:-http://localhost:3000/app} pnpm dev"
    "WS_ENDPOINT=ws://127.0.0.1:9231/debug node server.js"
    "WS_ENDPOINT=ws://[::1]:9232/debug node server.js"
    "INSPECT_PORT=\${INSPECT_PORT=9333} node --inspect app.js"
    "node --inspect=9229 app.js"
    "node --inspect=127.0.0.1:9229 app.js"
    "node --inspect-brk=localhost app.js"
    "node --inspect-port=127.0.0.1:9230 app.js"
    "node --inspect-wait=127.0.0.1:9330 app.js"
    "node --inspect-wait=::1 app.js"
    "next dev --hostname [::1] --port=3000"
    "vite --hmr-port 24678 --server-port=5173"
    "node server.js --debug-port=127.0.0.1:9230"
    "node server.js --api-port 8080 --ui-port=localhost:3000 --metrics-port 127.0.0.1:9090"
    "bun --hot server.ts --port 3002"
    "bun --watch --inspect-wait=127.0.0.1:9330 server.ts"
    "deno serve --listen 0.0.0.0:8787"
    "deno serve --listen 8790 --addr=8791"
    "PORT=8788 deno task dev"
    "deno task dev -- --listen 127.0.0.1:8789"
    "java -Dserver.port=8080 -Dmanagement.server.port=127.0.0.1:9001 -jar app.jar"
  )

  echo "=== Sample command extraction ==="
  for command in "${samples[@]}"; do
    echo ""
    echo "Command: $command"
    extract_ports "$command"
  done
}

MODE="all"
CUSTOM_COMMAND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live-only)
      MODE="live"
      ;;
    --samples-only)
      MODE="samples"
      ;;
    --command)
      shift
      if [[ $# -eq 0 ]]; then
        echo "❌ Missing value for --command" >&2
        usage >&2
        exit 2
      fi
      MODE="command"
      CUSTOM_COMMAND="$1"
      ;;
    --command=*)
      MODE="command"
      CUSTOM_COMMAND="${1#--command=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "❌ Unknown option: ${1}" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$MODE" == "command" ]]; then
  if [[ -z "$CUSTOM_COMMAND" ]]; then
    echo "❌ --command requires a non-empty value" >&2
    exit 2
  fi
  echo "=== Single command extraction ==="
  echo "Command: $CUSTOM_COMMAND"
  extract_ports "$CUSTOM_COMMAND"
  exit 0
fi

if [[ "$MODE" == "all" || "$MODE" == "live" ]]; then
  show_live_processes
fi

if [[ "$MODE" == "all" || "$MODE" == "samples" ]]; then
  echo ""
  show_samples
fi
