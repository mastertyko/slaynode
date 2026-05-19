#!/bin/bash
set -euo pipefail

# Test script to simulate different types of development servers
# This helps verify that SlayNode can detect various server types

DURATION_SECONDS="${1:-3600}"
PIDS=()

if ! [[ "$DURATION_SECONDS" =~ ^[0-9]+$ ]] || [[ "$DURATION_SECONDS" -lt 1 ]]; then
  echo "❌ Usage: $0 [duration-seconds>=1]" >&2
  exit 2
fi

cleanup() {
  if [[ ${#PIDS[@]} -eq 0 ]]; then
    return
  fi

  echo ""
  echo "🧹 Cleaning up simulated processes..."
  for pid in "${PIDS[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}

trap cleanup EXIT INT TERM

start_simulated_process() {
  local label="$1"
  local command_line="$2"

  /bin/bash -c "exec -a '$command_line' sleep '$DURATION_SECONDS'" &
  local pid=$!
  PIDS+=("${pid}")

  echo "${label} test process PID: ${pid}"
  echo "   Simulated command: ${command_line}"
}

echo "🚀 Starting test development servers..."
echo "You can run these in separate terminal windows to test SlayNode detection"
echo "Simulation duration per process: ${DURATION_SECONDS}s"
echo ""

echo "1. Next.js dev server (simulated):"
echo "   /bin/bash -c \"exec -a 'node .../next dev --port 3000' sleep ${DURATION_SECONDS}\" &"
echo ""

echo "2. Vite dev server (simulated):"
echo "   /bin/bash -c \"exec -a 'node .../vite --host 0.0.0.0 --port 5173' sleep ${DURATION_SECONDS}\" &"
echo ""

echo "3. Express server (simulated):"
echo "   /bin/bash -c \"exec -a 'node .../server.js --inspect=127.0.0.1:9229' sleep ${DURATION_SECONDS}\" &"
echo ""

echo "4. Create actual test processes:"
echo ""

# Create some test processes that simulate different server types
echo "Starting simulated Next.js process..."
start_simulated_process \
  "Next.js" \
  "node /Users/demo/app/node_modules/.bin/next dev --port 3000"

echo "Starting simulated Vite process..."
start_simulated_process \
  "Vite" \
  "node /Users/demo/app/node_modules/.bin/vite --host 0.0.0.0 --port 5173"

echo "Starting simulated Express process..."
start_simulated_process \
  "Express" \
  "node /Users/demo/api/server.js --inspect=127.0.0.1:9229"

echo ""
echo "Test processes started. Open SlayNode to see if they're detected."
echo "Press Enter (or Ctrl+C) to stop all simulated processes."
read -r _
