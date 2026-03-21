#!/bin/bash

# Test script to simulate different types of development servers
# This helps verify that Slaynode can detect various server types

echo "🚀 Starting test development servers..."
echo "You can run these in separate terminal windows to test Slaynode detection"
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
echo "Next.js test process PID: $NEXT_PID"

echo "Starting simulated Vite process..."  
sleep 3600 &
VITE_PID=$!
echo "Vite test process PID: $VITE_PID"

echo "Starting simulated Express process..."
sleep 3600 &
EXPR_PID=$!
echo "Express test process PID: $EXPR_PID"

echo ""
echo "Test processes started. Open Slaynode to see if they're detected."
echo "To stop all test processes: kill $NEXT_PID $VITE_PID $EXPR_PID"
