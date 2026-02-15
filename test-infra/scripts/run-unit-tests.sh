#!/bin/bash
# Grid Mobile — Unit Test Runner
# Usage: ./test-infra/scripts/run-unit-tests.sh [--coverage] [--ci]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_DIR"

COVERAGE=false
CI_MODE=false

for arg in "$@"; do
  case $arg in
    --coverage) COVERAGE=true ;;
    --ci) CI_MODE=true ;;
  esac
done

echo "🧪 Running Grid Mobile unit tests..."
echo "   Project: $PROJECT_DIR"
echo ""

FLUTTER_ARGS="test"

if [ "$COVERAGE" = true ]; then
  FLUTTER_ARGS="$FLUTTER_ARGS --coverage"
fi

if [ "$CI_MODE" = true ]; then
  # Machine-readable output for CI
  FLUTTER_ARGS="$FLUTTER_ARGS --machine"
  flutter $FLUTTER_ARGS 2>&1 | tee test-results.json
  EXIT_CODE=${PIPESTATUS[0]}
else
  flutter $FLUTTER_ARGS --reporter expanded
  EXIT_CODE=$?
fi

if [ "$COVERAGE" = true ] && [ -f coverage/lcov.info ]; then
  echo ""
  echo "📊 Coverage report generated: coverage/lcov.info"

  # Generate HTML report if lcov/genhtml is available
  if command -v genhtml &>/dev/null; then
    genhtml coverage/lcov.info -o coverage/html --quiet
    echo "   HTML report: coverage/html/index.html"
  else
    echo "   (install lcov for HTML report: brew install lcov)"
  fi
fi

echo ""
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ All tests passed!"
else
  echo "❌ Some tests failed (exit code: $EXIT_CODE)"
fi

exit $EXIT_CODE
