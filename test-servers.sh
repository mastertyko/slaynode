#!/bin/bash
set -euo pipefail

# Test script to simulate different types of development servers
# This helps verify that SlayNode can detect various server types

PIDS=()

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

echo "🚀 Starting test development servers..."
echo "You can run these in separate terminal windows to test SlayNode detection"
echo ""

echo "1. Next.js dev server (simulated):"
echo "   sleep 3600 &"
echo "   echo 'Simulating: npx next dev' with PID \$!"
echo ""

echo "2. Vite dev server (simulated):"
echo "   sleep 3600 &"
echo "   echo 'Simulating: npm run dev' with PID \$!"
echo ""

echo "3. Express server (simulated):"
echo "   sleep 3600 &"
echo "   echo 'Simulating: node server.js' with PID \$!"
echo ""

echo "4. Create actual test processes:"
echo ""

# Create some test processes that simulate different server types
echo "Starting simulated Next.js process..."
sleep 3600 &
NEXT_PID=$!
PIDS+=("${NEXT_PID}")
echo "Next.js test process PID: $NEXT_PID"

echo "Starting simulated Vite process..."  
sleep 3600 &
VITE_PID=$!
PIDS+=("${VITE_PID}")
echo "Vite test process PID: $VITE_PID"

echo "Starting simulated Express process..."
sleep 3600 &
EXPR_PID=$!
PIDS+=("${EXPR_PID}")
echo "Express test process PID: $EXPR_PID"

echo ""
echo "Test processes started. Open SlayNode to see if they're detected."
echo "Press Enter (or Ctrl+C) to stop all simulated processes."
read -r _
