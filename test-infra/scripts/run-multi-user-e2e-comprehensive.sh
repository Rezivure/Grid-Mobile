#!/bin/bash
# run-multi-user-e2e-comprehensive.sh
# Comprehensive multi-user E2E test runner for Grid-Mobile
# Runs the high-priority Matrix API + Maestro integration tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
SYNAPSE_URL="${SYNAPSE_URL:-http://localhost:8008}"
TEST_USER="testuser1"
TEST_PASS="testpass123"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

print_header() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  Grid-Mobile Multi-User E2E Test Suite${NC}"
    echo -e "${BLUE}  Testing Matrix API integration + Maestro UI verification${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Docker is running (for Synapse)
    if ! docker ps > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker."
        exit 1
    fi
    
    # Check if Synapse is accessible
    if ! curl -s "$SYNAPSE_URL/_matrix/client/versions" > /dev/null; then
        print_error "Synapse server not accessible at $SYNAPSE_URL"
        print_error "Please start the Synapse test server."
        exit 1
    fi
    
    # Check if Maestro is installed
    if ! command -v maestro &> /dev/null; then
        print_error "Maestro CLI not found. Please install Maestro."
        exit 1
    fi
    
    # Check if Flutter app is ready
    if [ ! -d "$PROJECT_ROOT/.maestro" ]; then
        print_error "Maestro test directory not found at $PROJECT_ROOT/.maestro"
        exit 1
    fi
    
    # Check test accounts exist
    source "$SCRIPT_DIR/api-helpers.sh"
    if ! login_as_user "$TEST_USER" "$TEST_PASS"; then
        print_error "Test account $TEST_USER not accessible. Please run setup-accounts.sh"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Clean up test state before starting
cleanup_test_state() {
    print_status "Cleaning up test state..."
    
    source "$SCRIPT_DIR/api-helpers.sh"
    cleanup_test_state
    
    # Clean up temp files
    rm -f /tmp/test_*_room_id
    rm -f /tmp/testuser*_room
    
    print_success "Test state cleaned up"
}

# Run a single Maestro test
run_maestro_test() {
    local test_file="$1"
    local test_name="$2"
    
    print_status "Running: $test_name"
    echo "  File: $test_file"
    
    ((TESTS_RUN++))
    
    # Run the Maestro test with timeout
    if timeout 300 maestro test "$test_file" > /tmp/maestro_output.log 2>&1; then
        print_success "$test_name - PASSED"
        ((TESTS_PASSED++))
    else
        print_error "$test_name - FAILED"
        echo "  Error output:"
        tail -10 /tmp/maestro_output.log | sed 's/^/    /'
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
    fi
    
    echo ""
}

# Main test suite
run_test_suite() {
    print_status "Starting multi-user E2E test suite..."
    echo ""
    
    cd "$PROJECT_ROOT"
    
    # Define test cases in priority order
    declare -A TESTS=(
        ["e2e_01_incoming_location_sharing.yaml"]="Location Sharing E2E"
        ["e2e_02_friend_request_received.yaml"]="Friend Request Notification"
        ["e2e_03_group_invite_received.yaml"]="Group Invitation Flow"
        ["e2e_04_multiple_locations_map.yaml"]="Multiple Simultaneous Locations"
        ["e2e_05_group_member_locations.yaml"]="Group Member Location Updates"
        ["e2e_06_display_name_propagation.yaml"]="Display Name Change Propagation"
        ["e2e_07_user_presence_status.yaml"]="User Presence/Status Updates"
        ["e2e_08_removed_from_group.yaml"]="Group Removal/Kick Handling"
        ["e2e_09_friend_request_accepted_api.yaml"]="Friend Request Acceptance API Verification"
    )
    
    # Run each test
    for test_file in "${!TESTS[@]}"; do
        local test_path=".maestro/$test_file"
        local test_name="${TESTS[$test_file]}"
        
        if [ -f "$test_path" ]; then
            # Clean state before each test
            cleanup_test_state
            sleep 2  # Give time for cleanup
            
            run_maestro_test "$test_path" "$test_name"
            
            # Wait between tests to avoid conflicts
            sleep 3
        else
            print_warning "Test file not found: $test_path"
        fi
    done
}

# Print final results
print_results() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  Test Results Summary${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
    echo -e "Total tests run: ${TESTS_RUN}"
    echo -e "${GREEN}Tests passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Tests failed: ${TESTS_FAILED}${NC}"
    
    if [ ${TESTS_FAILED} -gt 0 ]; then
        echo ""
        echo -e "${RED}Failed tests:${NC}"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo -e "  - $failed_test"
        done
    fi
    
    echo ""
    echo -e "Success rate: $(( (TESTS_PASSED * 100) / TESTS_RUN ))%"
    
    if [ ${TESTS_FAILED} -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed.${NC}"
        exit 1
    fi
}

# Additional test scenarios
run_stress_tests() {
    print_status "Running stress test scenarios..."
    
    # Test with many simultaneous users (if enabled)
    if [ "$RUN_STRESS_TESTS" = "true" ]; then
        print_status "Setting up 8 users with simultaneous location updates..."
        
        source "$SCRIPT_DIR/api-helpers.sh"
        
        # Create a stress test scenario
        for i in {2..9}; do
            login_as_user "testuser$i"
            ROOM_ID=$(grid_create_direct "testuser1")
            # Random NYC coordinates
            LAT=$(awk "BEGIN {printf \"%.4f\", 40.7 + (rand() * 0.1)}")
            LON=$(awk "BEGIN {printf \"%.4f\", -74.0 + (rand() * 0.1)}")
            grid_send_location "$ROOM_ID" "$LAT" "$LON"
        done
        
        wait_for_sync 10
        print_success "Stress test setup complete"
    fi
}

# Performance monitoring
monitor_performance() {
    if [ "$MONITOR_PERFORMANCE" = "true" ]; then
        print_status "Performance monitoring enabled..."
        
        # Monitor app memory/CPU during tests
        # This would integrate with device monitoring tools
        print_status "Monitoring app performance during tests..."
    fi
}

# Main execution
main() {
    print_header
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --stress)
                export RUN_STRESS_TESTS=true
                shift
                ;;
            --performance)
                export MONITOR_PERFORMANCE=true
                shift
                ;;
            --cleanup-only)
                cleanup_test_state
                exit 0
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --stress         Run stress tests with many users"
                echo "  --performance    Enable performance monitoring"
                echo "  --cleanup-only   Only clean up test state and exit"
                echo "  --help          Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    cleanup_test_state
    
    # Start performance monitoring if enabled
    if [ "$MONITOR_PERFORMANCE" = "true" ]; then
        monitor_performance &
        MONITOR_PID=$!
    fi
    
    # Run the main test suite
    run_test_suite
    
    # Run stress tests if enabled
    if [ "$RUN_STRESS_TESTS" = "true" ]; then
        run_stress_tests
    fi
    
    # Stop performance monitoring
    if [ -n "$MONITOR_PID" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
    
    print_results
}

# Trap cleanup on exit
trap 'cleanup_test_state 2>/dev/null || true' EXIT

# Run main function
main "$@"