#!/bin/bash
# Full E2E test runner for Grid
# Usage: ./run-tests.sh [--keep] [--no-maestro]
#
# --keep       Don't tear down Docker after tests
# --no-maestro Only spin up infra, skip Maestro flows

set -e
cd "$(dirname "$0")/.."

KEEP=false
NO_MAESTRO=false

for arg in "$@"; do
  case $arg in
    --keep) KEEP=true ;;
    --no-maestro) NO_MAESTRO=true ;;
  esac
done

echo "🔧 Starting test infrastructure..."
docker compose up -d --wait

echo ""
echo "✅ Synapse is running on http://localhost:8008"
echo ""

# Run account setup (runs automatically via docker compose, but wait for it)
echo "👥 Waiting for account setup..."
docker compose logs -f test-setup 2>/dev/null || true
echo ""

if [ "$NO_MAESTRO" = false ]; then
  echo "🧪 Running Maestro E2E tests..."
  echo ""

  # Set the simulator location to NYC for consistent test results
  xcrun simctl location booted set 40.7128,-74.0060 2>/dev/null || true

  # Run all Maestro flows
  export PATH="$PATH:$HOME/.maestro/bin"
  maestro test ../.maestro/

  echo ""
  echo "✅ All tests complete!"
fi

if [ "$KEEP" = false ]; then
  echo ""
  echo "🧹 Tearing down..."
  docker compose down -v
else
  echo ""
  echo "📦 Infrastructure still running (--keep). Tear down with:"
  echo "   cd test-infra && docker compose down -v"
fi
