#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

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
    fail "expected output not to contain '${needle}'"
  fi
}

assert_ports() {
  local command="$1"
  shift

  local output
  output="$("${ROOT_DIR}/debug-port-detection.sh" --command "${command}")"

  for expected in "$@"; do
    assert_contains "${output}" "  :${expected}"
  done
}

assert_no_ports() {
  local command="$1"

  local output
  output="$("${ROOT_DIR}/debug-port-detection.sh" --command "${command}")"
  assert_contains "${output}" "  (inga port-träffar)"
  assert_not_contains "${output}" "  :"
}

assert_ports "bun --hot server.ts --port 3002" 3002
assert_ports "rails server -p 3003" 3003
assert_ports "python manage.py runserver 8000" 8000
assert_ports "python3 -m http.server 8080" 8080
assert_ports "python3 -m http.server --bind 127.0.0.1 --directory public 8081" 8081
assert_ports "streamlit run app.py --server.port 8502" 8502
assert_ports "gradio app.py --server-port 7861" 7861
assert_ports "hypercorn app:app --bind 127.0.0.1:8003" 8003
assert_ports "waitress-serve --listen=0.0.0.0:8082 app:app" 8082
assert_ports "puma -p3004" 3004
assert_ports "bun --watch --inspect-wait=127.0.0.1:9330 server.ts" 9330
assert_ports "PORT=8788 deno task dev" 8788
assert_ports "web_port=5174 npm run dev" 5174
assert_no_ports "REPORT=1234 npm run dev"
assert_ports "deno task dev -- --listen 127.0.0.1:8789" 8789
assert_ports "PUBLIC_URL=\${PUBLIC_URL:-http://localhost:3000/app} pnpm dev" 3000
assert_ports "WS_ENDPOINT=ws://127.0.0.1:9231/debug node server.js" 9231
assert_ports "WS_ENDPOINT=ws://[::1]:9232/debug node server.js" 9232
assert_ports "vite --hmr-port 24678 --server-port=5173" 5173 24678
assert_ports "node server.js --debug-port=127.0.0.1:9230 --dev-server-port localhost:3000" 3000 9230

echo "PASS: debug_port_detection"
