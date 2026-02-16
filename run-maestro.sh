#!/bin/bash
# Grid-Mobile Maestro Flow Runner
# Usage: ./run-maestro.sh [tier] [options]
# Tiers: core, extended, release
# Options: --report-dir DIR, --parallel N

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAESTRO_DIR="$SCRIPT_DIR/.maestro"
TIER_CONFIG="$MAESTRO_DIR/flow-tiers.yml"
REPORT_DIR="$SCRIPT_DIR/test-infra/reports/maestro"
PARALLEL=1

# Default tier
TIER="core"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [tier] [options]"
    echo ""
    echo "Tiers:"
    echo "  core     - Fast core flows for every push/PR (~5 min)"
    echo "  extended - Extended flows for pre-merge (~15 min)"
    echo "  release  - Full release validation (~30-60 min)"
    echo ""
    echo "Options:"
    echo "  --report-dir DIR  - Output directory for test reports"
    echo "  --parallel N      - Number of parallel flows (default: 1)"
    echo "  --list           - List flows for specified tier"
    echo "  --help           - Show this help"
}

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            core|extended|release)
                TIER="$1"
                shift
                ;;
            --report-dir)
                REPORT_DIR="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL="$2"
                shift 2
                ;;
            --list)
                LIST_ONLY=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

get_flows_for_tier() {
    local tier="$1"
    
    if [[ ! -f "$TIER_CONFIG" ]]; then
        error "Flow tiers config not found: $TIER_CONFIG"
        exit 1
    fi
    
    # Parse YAML to get flows for tier
    # This is a simple parser that assumes our specific format
    local in_tier=false
    local flows=()
    
    while IFS= read -r line; do
        # Remove leading spaces and comments
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/#.*$//')
        
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Check if we're entering our tier
        if [[ "$line" =~ ^${tier}:[[:space:]]*$ ]]; then
            in_tier=true
            continue
        fi
        
        # Check if we're entering a different tier
        if [[ "$line" =~ ^[a-z]+:[[:space:]]*$ ]]; then
            in_tier=false
            continue
        fi
        
        # If we're in our tier and this is a flow line
        if [[ "$in_tier" == true && "$line" =~ ^-[[:space:]]+(.*) ]]; then
            local flow="${BASH_REMATCH[1]}"
            flows+=("$flow")
        fi
    done < "$TIER_CONFIG"
    
    printf '%s\n' "${flows[@]}"
}

validate_flows() {
    local flows=("$@")
    local missing=()
    
    for flow in "${flows[@]}"; do
        if [[ ! -f "$MAESTRO_DIR/${flow}.yaml" ]]; then
            missing+=("$flow")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing flow files:"
        for flow in "${missing[@]}"; do
            echo "  - $flow.yaml"
        done
        return 1
    fi
    
    return 0
}

run_flow() {
    local flow="$1"
    local flow_file="$MAESTRO_DIR/${flow}.yaml"
    local report_file="$REPORT_DIR/${flow}.log"
    
    log "Running $flow..."
    
    mkdir -p "$REPORT_DIR"
    
    if maestro test "$flow_file" > "$report_file" 2>&1; then
        success "✓ $flow"
        return 0
    else
        error "✗ $flow"
        echo "  Last 3 lines from $report_file:"
        tail -3 "$report_file" | sed 's/^/    /'
        return 1
    fi
}

run_flows_sequential() {
    local flows=("$@")
    local passed=0
    local failed=0
    local start_time=$(date +%s)
    
    for flow in "${flows[@]}"; do
        if run_flow "$flow"; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    echo ""
    echo "═══════════════════════════════════════"
    echo "MAESTRO TEST RESULTS ($TIER tier)"
    echo "═══════════════════════════════════════"
    echo "Passed:   $passed"
    echo "Failed:   $failed"
    echo "Total:    $((passed + failed))"
    echo "Duration: ${minutes}m${seconds}s"
    echo ""
    
    if [[ $failed -gt 0 ]]; then
        error "Some tests failed. Check reports in: $REPORT_DIR"
        return 1
    else
        success "All tests passed!"
        return 0
    fi
}

main() {
    parse_args "$@"
    
    # Get flows for tier
    local flows
    mapfile -t flows < <(get_flows_for_tier "$TIER")
    
    if [[ ${#flows[@]} -eq 0 ]]; then
        error "No flows found for tier: $TIER"
        exit 1
    fi
    
    # List flows if requested
    if [[ "${LIST_ONLY:-}" == "true" ]]; then
        echo "Flows for tier '$TIER':"
        printf '  - %s\n' "${flows[@]}"
        echo ""
        echo "Total: ${#flows[@]} flows"
        exit 0
    fi
    
    # Validate flows exist
    if ! validate_flows "${flows[@]}"; then
        exit 1
    fi
    
    log "Running $TIER tier (${#flows[@]} flows)"
    log "Report directory: $REPORT_DIR"
    
    # Check if Maestro is available
    if ! command -v maestro >/dev/null 2>&1; then
        error "Maestro CLI not found in PATH"
        exit 1
    fi
    
    # Run flows
    if ! run_flows_sequential "${flows[@]}"; then
        exit 1
    fi
}

main "$@"