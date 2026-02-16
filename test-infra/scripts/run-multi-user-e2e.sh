#!/bin/bash
# run-multi-user-e2e.sh — Run comprehensive multi-user E2E tests
# These tests combine API setup with UI verification for real product scenarios

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAESTRO_DIR="$PROJECT_ROOT/.maestro"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo "  Grid Multi-User E2E Test Suite"
echo "========================================"
echo ""

# Check prerequisites
check_prerequisites() {
  echo "🔍 Checking prerequisites..."
  
  # Check if Docker is running
  if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}✗ Docker is not running. Please start Docker first.${NC}"
    exit 1
  fi
  
  # Check if Synapse is running
  if ! curl -s http://localhost:8008/_matrix/client/versions > /dev/null 2>&1; then
    echo -e "${RED}✗ Synapse server not accessible at localhost:8008${NC}"
    echo "  Run: cd test-infra && docker compose up -d"
    exit 1
  fi
  
  # Check if Maestro is installed
  if ! command -v maestro > /dev/null 2>&1; then
    echo -e "${RED}✗ Maestro is not installed or not in PATH${NC}"
    exit 1
  fi
  
  # Check if Grid app is available
  if ! maestro test --help > /dev/null 2>&1; then
    echo -e "${RED}✗ Maestro test command not working${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}✓ Prerequisites check passed${NC}"
  echo ""
}

# Clean up any existing test state
cleanup_state() {
  echo "🧹 Cleaning up test state..."
  
  cd "$SCRIPT_DIR"
  source api-helpers.sh > /dev/null 2>&1
  cleanup_test_state > /dev/null 2>&1 || true
  
  echo -e "${GREEN}✓ Test state cleaned${NC}"
  echo ""
}

# Run a single test with error handling
run_test() {
  local test_file="$1"
  local test_name="$2"
  
  echo -e "${BLUE}🔬 Running: $test_name${NC}"
  echo "   File: $test_file"
  
  cd "$PROJECT_ROOT"
  
  if timeout 300 maestro test "$MAESTRO_DIR/$test_file" > /tmp/maestro_output.log 2>&1; then
    echo -e "${GREEN}   ✓ PASSED${NC}"
    return 0
  else
    echo -e "${RED}   ✗ FAILED${NC}"
    echo "   Error log:"
    cat /tmp/maestro_output.log | tail -20 | sed 's/^/     /'
    echo ""
    return 1
  fi
}

# Multi-user E2E tests
TESTS=(
  "46_incoming_location_update.yaml:Incoming Location Update"
  "47_notification_badge_friend_request.yaml:Notification Badge (Friend Request)"
  "48_accept_group_invite_flow.yaml:Accept Group Invite Flow"
  "49_decline_group_invite_flow.yaml:Decline Group Invite Flow"
  "56_contact_goes_incognito.yaml:Contact Goes Incognito"
  "57_group_member_leaves.yaml:Group Member Leaves"
  "58_avatar_update_propagation.yaml:Avatar Update Propagation"
  "59_multiple_friend_requests.yaml:Multiple Friend Requests"
  "60_location_history_trail.yaml:Location History Trail"
  "61_sign_out_clean_state.yaml:Sign Out Clean State"
)

# Test execution
main() {
  local failed_tests=()
  local passed_tests=()
  local run_specific=""
  
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --test)
        run_specific="$2"
        shift 2
        ;;
      --help)
        echo "Usage: $0 [--test <test_name>] [--help]"
        echo ""
        echo "Available tests:"
        for test in "${TESTS[@]}"; do
          test_file=$(echo "$test" | cut -d':' -f1)
          test_name=$(echo "$test" | cut -d':' -f2)
          echo "  $test_file - $test_name"
        done
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
  done
  
  check_prerequisites
  cleanup_state
  
  echo "🚀 Starting multi-user E2E test execution..."
  echo ""
  
  local start_time=$(date +%s)
  
  # Ensure testuser1 is logged in first
  echo -e "${YELLOW}📱 Ensuring testuser1 is logged in...${NC}"
  cd "$PROJECT_ROOT"
  if ! timeout 180 maestro test "$MAESTRO_DIR/04_login_local_server.yaml" > /dev/null 2>&1; then
    echo -e "${RED}✗ Failed to log in testuser1. Cannot continue with multi-user tests.${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ testuser1 logged in successfully${NC}"
  echo ""
  
  # Run tests
  for test in "${TESTS[@]}"; do
    test_file=$(echo "$test" | cut -d':' -f1)
    test_name=$(echo "$test" | cut -d':' -f2)
    
    # Skip if running specific test and this isn't it
    if [[ -n "$run_specific" && "$test_file" != "$run_specific" && "$test_name" != "$run_specific" ]]; then
      continue
    fi
    
    if run_test "$test_file" "$test_name"; then
      passed_tests+=("$test_name")
    else
      failed_tests+=("$test_name")
    fi
    
    # Brief pause between tests
    sleep 2
    
    # Cleanup between tests
    cleanup_state > /dev/null 2>&1 || true
  done
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  # Results summary
  echo "========================================"
  echo "  Multi-User E2E Test Results"
  echo "========================================"
  echo -e "${GREEN}✓ Passed: ${#passed_tests[@]}${NC}"
  echo -e "${RED}✗ Failed: ${#failed_tests[@]}${NC}"
  echo "⏱️  Duration: ${duration}s"
  echo ""
  
  if [[ ${#passed_tests[@]} -gt 0 ]]; then
    echo -e "${GREEN}Passed tests:${NC}"
    for test in "${passed_tests[@]}"; do
      echo "  ✓ $test"
    done
    echo ""
  fi
  
  if [[ ${#failed_tests[@]} -gt 0 ]]; then
    echo -e "${RED}Failed tests:${NC}"
    for test in "${failed_tests[@]}"; do
      echo "  ✗ $test"
    done
    echo ""
    exit 1
  fi
  
  echo -e "${GREEN}🎉 All multi-user E2E tests passed!${NC}"
}

main "$@"