#!/bin/bash

echo "=== Testing actual ps command output ==="
ps -axo pid=,command= | grep -E '^[ ]*[0-9]+ (node |npm |yarn |pnpm |npx )' | head -5

echo ""
echo "=== Testing port extraction patterns ==="
# Test a few sample commands
echo "Command: npm run dev -- --port 3001"
echo "npm run dev -- --port 3001" | grep -o ':[0-9]\{3,5\}' | head -3

echo ""
echo "Command: node server.js --port 8080"
echo "node server.js --port 8080" | grep -o ':[0-9]\{3,5\}' | head -3

echo ""
echo "Command: vite --port 5173"
echo "vite --port 5173" | grep -o ':[0-9]\{3,5\}' | head -3

echo ""
echo "=== Real Node.js processes ==="
ps -axo pid=,command= | grep -E '(node |npm |yarn |pnpm |npx )' | head -10