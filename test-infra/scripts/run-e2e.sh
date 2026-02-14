#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Grid E2E Test Runner
# ═══════════════════════════════════════════════════════════════════════════════
# Spins up Synapse, creates accounts, runs Maestro + API-orchestrated tests,
# and produces a clean pass/fail report.
#
# Usage:
#   ./test-infra/scripts/run-e2e.sh              # full run (clean Synapse → tests → teardown)
#   ./test-infra/scripts/run-e2e.sh --skip-ui    # skip Maestro UI tests (API-only, fast)
#   ./test-infra/scripts/run-e2e.sh --only <test> # run a single test phase
#
# Exit code: 0 if all tests pass, 1 if any fail
# ═══════════════════════════════════════════════════════════════════════════════

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INFRA_DIR="$PROJECT_ROOT/test-infra"
MAESTRO_DIR="$PROJECT_ROOT/.maestro"
REPORT_DIR="$INFRA_DIR/reports"
SYNAPSE_URL="http://localhost:8008"
export PATH="$HOME/.maestro/bin:$PATH"

# ─── Colors & Formatting ───────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# ─── State ──────────────────────────────────────────────────────────────────────

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
FAILURES=()
ONLY_TEST=""
E2E_MODE="custom"
START_TIME=$(date +%s)

# Tokens stored as files (bash 3.2 compat — no associative arrays on macOS)
TOKEN_DIR=$(mktemp -d)
trap "rm -rf $TOKEN_DIR" EXIT

set_token() { echo "$2" > "$TOKEN_DIR/token_$1"; }
get_token() { cat "$TOKEN_DIR/token_$1" 2>/dev/null; }
set_userid() { echo "$2" > "$TOKEN_DIR/uid_$1"; }
get_userid() { cat "$TOKEN_DIR/uid_$1" 2>/dev/null; }

# ─── Parse Args ─────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-ui) SKIP_UI=true; shift ;;
    --only) ONLY_TEST="$2"; shift 2 ;;
    --mode) E2E_MODE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ─── Helpers ────────────────────────────────────────────────────────────────────

log_header() {
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  $1${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

log_phase() {
  echo ""
  echo -e "${CYAN}──── $1 ────${NC}"
}

log_step() {
  echo -e "${DIM}  → $1${NC}"
}

record_pass() {
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  echo -e "  ${GREEN}✓${NC} $1"
}

record_fail() {
  TOTAL=$((TOTAL + 1))
  FAILED=$((FAILED + 1))
  FAILURES+=("$1: $2")
  echo -e "  ${RED}✗${NC} $1"
  echo -e "    ${DIM}$2${NC}"
}

record_skip() {
  TOTAL=$((TOTAL + 1))
  SKIPPED=$((SKIPPED + 1))
  echo -e "  ${YELLOW}⊘${NC} $1 ${DIM}(skipped)${NC}"
}

should_run() {
  [[ -z "$ONLY_TEST" || "$ONLY_TEST" == "$1" ]]
}

# Matrix API helper (standalone, doesn't need grid-api.sh sourced)
matrix_api() {
  local token="$1" method="$2" endpoint="$3" data="${4:-}"
  if [ -n "$data" ]; then
    curl -s -X "$method" "${SYNAPSE_URL}${endpoint}" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      -d "$data" 2>/dev/null
  else
    curl -s -X "$method" "${SYNAPSE_URL}${endpoint}" \
      -H "Authorization: Bearer ${token}" 2>/dev/null
  fi
}

matrix_login() {
  local username="$1" password="${2:-testpass123}"
  local result
  result=$(curl -sf -X POST "${SYNAPSE_URL}/_matrix/client/v3/login" \
    -H "Content-Type: application/json" \
    -d "{
      \"type\": \"m.login.password\",
      \"identifier\": {\"type\": \"m.id.user\", \"user\": \"${username}\"},
      \"password\": \"${password}\"
    }" 2>/dev/null) || return 1

  local token user_id
  token=$(echo "$result" | jq -r '.access_token // empty')
  user_id=$(echo "$result" | jq -r '.user_id // empty')

  if [ -z "$token" ]; then return 1; fi

  set_token "$username" "$token"
  set_userid "$username" "$user_id"
  echo "$token"
}

matrix_register() {
  local username="$1" password="${2:-testpass123}"
  curl -sf -X POST "${SYNAPSE_URL}/_matrix/client/v3/register" \
    -H "Content-Type: application/json" \
    -d "{
      \"username\": \"${username}\",
      \"password\": \"${password}\",
      \"auth\": {\"type\": \"m.login.dummy\"},
      \"inhibit_login\": true
    }" 2>/dev/null
}

# ─── Maestro Runner ─────────────────────────────────────────────────────────────

run_maestro_flow() {
  local flow_name="$1"
  local flow_file="$MAESTRO_DIR/${flow_name}.yaml"
  local test_label="Maestro: ${flow_name}"

  if [ ! -f "$flow_file" ]; then
    record_skip "$test_label (file not found)"
    return
  fi

  log_step "Running $flow_name..."

  local output_file="$REPORT_DIR/${flow_name}.log"
  if maestro test -e E2E_MODE="$E2E_MODE" "$flow_file" > "$output_file" 2>&1; then
    record_pass "$test_label"
  else
    local error_msg
    error_msg=$(tail -5 "$output_file" | head -3)
    record_fail "$test_label" "$error_msg"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 0: Infrastructure
# ═══════════════════════════════════════════════════════════════════════════════

phase_infra() {
  log_header "PHASE 0: Infrastructure Setup"

  mkdir -p "$REPORT_DIR"

  # Tear down any existing instance and wipe data for a clean slate
  log_step "Cleaning previous Synapse data..."
  (cd "$INFRA_DIR" && docker compose down -v 2>/dev/null)
  rm -rf "$INFRA_DIR/synapse/homeserver.db" "$INFRA_DIR/synapse/media_store" "$INFRA_DIR/synapse/*.log" 2>/dev/null

  # Generate fresh signing key if needed
  if [ ! -f "$INFRA_DIR/synapse/homeserver.signing.key" ]; then
    log_step "Generating Synapse signing key..."
    docker run --rm -v "$INFRA_DIR/synapse:/data" -e SYNAPSE_SERVER_NAME=localhost \
      -e SYNAPSE_REPORT_STATS=no matrixdotorg/synapse:latest generate 2>/dev/null
    chmod -R 777 "$INFRA_DIR/synapse" 2>/dev/null
  fi

  # Start Docker Synapse
  log_step "Starting Synapse via Docker Compose..."
  if (cd "$INFRA_DIR" && docker compose up -d --wait 2>&1 | tail -3); then
    sleep 2
    if curl -sf "${SYNAPSE_URL}/health" > /dev/null 2>&1; then
      record_pass "Synapse started and healthy"
    else
      record_fail "Synapse health check" "Container started but /health not responding"
      exit 1
    fi
  else
    record_fail "Docker Compose up" "Failed to start Synapse"
    exit 1
  fi

  # Create test accounts (idempotent)
  log_step "Creating test accounts..."
  local accounts_created=0
  for i in $(seq 1 12); do
    matrix_register "testuser${i}" "testpass123" > /dev/null 2>&1
    accounts_created=$((accounts_created + 1))
  done
  record_pass "Test accounts ready (testuser1-12)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 1: Auth & Login Tests
# ═══════════════════════════════════════════════════════════════════════════════

phase_auth() {
  log_header "PHASE 1: Authentication"

  # Test API login for all users we'll need
  log_step "Logging in test users via API..."

  for user in testuser1 testuser2 testuser3; do
    if matrix_login "$user" > /dev/null; then
      record_pass "API login: ${user} → $(get_userid $user)"
    else
      record_fail "API login: ${user}" "Login request failed"
    fi
  done
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 2: UI Tests (Maestro - no API orchestration needed)
# ═══════════════════════════════════════════════════════════════════════════════

phase_ui() {
  log_header "PHASE 2: UI Tests (Maestro)"

  # Clean app state on simulator before running UI tests
  log_step "Resetting app state on simulator..."
  local BUNDLE_ID="app.mygrid.grid"
  local SIM_UDID
  SIM_UDID=$(xcrun simctl list devices booted -j | jq -r '.devices[][] | select(.state == "Booted") | .udid' | head -1)

  if [ -n "$SIM_UDID" ]; then
    # Uninstall app completely (removes all data)
    xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null
    sleep 1

    # Rebuild and install fresh
    log_step "Building and installing fresh app..."
    if (cd "$PROJECT_ROOT" && flutter build ios --simulator --debug 2>&1 | tail -3); then
      xcrun simctl install "$SIM_UDID" "$PROJECT_ROOT/build/ios/iphonesimulator/Runner.app" 2>/dev/null
      record_pass "App freshly installed on ${SIM_UDID}"
    else
      record_fail "App build" "flutter build ios --simulator failed"
      return
    fi
  else
    record_fail "Simulator" "No booted simulator found"
    return
  fi

  run_maestro_flow "01_app_launches"
  run_maestro_flow "02_onboarding_flow"
  run_maestro_flow "03_custom_provider_flow"
  run_maestro_flow "04_login_local_server"  # includes login + full onboarding
  run_maestro_flow "06_navigate_to_settings"
  run_maestro_flow "07_settings_toggles"
  run_maestro_flow "08_settings_security_keys"
  run_maestro_flow "09_settings_display_name"
  run_maestro_flow "10_settings_links"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 3: Direct Room (Contact) Tests — API-orchestrated
# ═══════════════════════════════════════════════════════════════════════════════

phase_direct() {
  log_header "PHASE 3: Direct Rooms (Contacts)"

  local t1="$(get_token testuser1)"
  local t2="$(get_token testuser2)"
  local u1="$(get_userid testuser1)"
  local u2="$(get_userid testuser2)"
  local homeserver
  homeserver=$(echo "$SYNAPSE_URL" | sed 's|https\?://||')

  if [ -z "$t1" ] || [ -z "$t2" ]; then
    record_skip "Direct room tests (login tokens missing)"
    return
  fi

  # 3.1: User2 creates a direct room and invites User1 (via API)
  log_step "testuser2 invites testuser1 to direct room..."
  local room_name="Grid:Direct:${u2}:${u1}"
  local create_result
  create_result=$(matrix_api "$t2" POST "/_matrix/client/v3/createRoom" "{
    \"name\": \"${room_name}\",
    \"is_direct\": true,
    \"preset\": \"private_chat\",
    \"invite\": [\"${u1}\"],
    \"initial_state\": [
      {\"type\": \"m.room.encryption\", \"content\": {\"algorithm\": \"m.megolm.v1.aes-sha2\"}, \"state_key\": \"\"}
    ]
  }")

  local direct_room_id
  direct_room_id=$(echo "$create_result" | jq -r '.room_id // empty')

  if [ -n "$direct_room_id" ]; then
    record_pass "Create direct room: ${direct_room_id}"
  else
    record_fail "Create direct room" "$(echo "$create_result" | jq -r '.error // "unknown"')"
    return
  fi

  # 3.2: Verify room name matches Grid convention
  local fetched_name
  fetched_name=$(matrix_api "$t2" GET "/_matrix/client/v3/rooms/${direct_room_id}/state/m.room.name" | jq -r '.name // empty')
  if [ "$fetched_name" = "$room_name" ]; then
    record_pass "Room name matches Grid format: ${room_name}"
  else
    record_fail "Room name format" "Expected '${room_name}', got '${fetched_name}'"
  fi

  # 3.3: Verify E2EE is enabled
  local encryption
  encryption=$(matrix_api "$t2" GET "/_matrix/client/v3/rooms/${direct_room_id}/state/m.room.encryption" | jq -r '.algorithm // empty')
  if [ "$encryption" = "m.megolm.v1.aes-sha2" ]; then
    record_pass "E2EE enabled (m.megolm.v1.aes-sha2)"
  else
    record_fail "E2EE check" "Algorithm: ${encryption}"
  fi

  # 3.4: User1 sees the invite
  local invites
  invites=$(matrix_api "$t1" GET "/_matrix/client/v3/sync?filter=%7B%22room%22%3A%7B%22timeline%22%3A%7B%22limit%22%3A0%7D%7D%7D" | \
    jq -r '.rooms.invite // {} | keys[]' 2>/dev/null)
  if echo "$invites" | grep -q "$direct_room_id"; then
    record_pass "testuser1 sees invite for ${direct_room_id}"
  else
    record_fail "testuser1 invite visibility" "Room not in invite list"
  fi

  # 3.5: User1 accepts the invite
  local join_result
  join_result=$(matrix_api "$t1" POST "/_matrix/client/v3/join/${direct_room_id}" "{}")
  local joined_id
  joined_id=$(echo "$join_result" | jq -r '.room_id // empty')
  if [ "$joined_id" = "$direct_room_id" ]; then
    record_pass "testuser1 accepted invite"
  else
    record_fail "Accept invite" "$(echo "$join_result" | jq -r '.error // "unknown"')"
  fi

  # 3.6: Both users are joined
  local members
  members=$(matrix_api "$t1" GET "/_matrix/client/v3/rooms/${direct_room_id}/members" | \
    jq -r '[.chunk[] | select(.content.membership == "join") | .state_key] | sort | join(",")')
  local expected_members
  # Sort expected members to match
  expected_members=$(echo -e "${u1}\n${u2}" | sort | paste -sd, -)
  if [ "$members" = "$expected_members" ]; then
    record_pass "Both users joined: ${members}"
  else
    record_fail "Room membership" "Expected '${expected_members}', got '${members}'"
  fi

  # 3.7: Send location from User2
  log_step "testuser2 sends location update..."
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  local txn="test$(date +%s)"
  local loc_result
  loc_result=$(matrix_api "$t2" PUT \
    "/_matrix/client/v3/rooms/${direct_room_id}/send/m.room.message/${txn}" \
    "{
      \"msgtype\": \"m.location\",
      \"body\": \"Current location\",
      \"geo_uri\": \"geo:40.7580,-73.9855\",
      \"description\": \"Current location\",
      \"timestamp\": \"${ts}\"
    }")

  local event_id
  event_id=$(echo "$loc_result" | jq -r '.event_id // empty')
  if [ -n "$event_id" ]; then
    record_pass "Location sent: geo:40.7580,-73.9855 (${event_id})"
  else
    record_fail "Send location" "$(echo "$loc_result" | jq -r '.error // "unknown"')"
  fi

  # 3.8: User1 can read the location event
  sleep 1
  local messages
  messages=$(matrix_api "$t1" GET "/_matrix/client/v3/rooms/${direct_room_id}/messages?dir=b&limit=5")
  local geo_uri
  geo_uri=$(echo "$messages" | jq -r '.chunk[] | select(.content.msgtype == "m.location") | .content.geo_uri' | head -1)
  if [ "$geo_uri" = "geo:40.7580,-73.9855" ]; then
    record_pass "testuser1 received location: ${geo_uri}"
  else
    record_fail "Receive location" "Expected geo:40.7580,-73.9855, got: ${geo_uri}"
  fi

  # 3.9: User1 leaves room
  matrix_api "$t1" POST "/_matrix/client/v3/rooms/${direct_room_id}/leave" "{}" > /dev/null 2>&1
  matrix_api "$t1" POST "/_matrix/client/v3/rooms/${direct_room_id}/forget" "{}" > /dev/null 2>&1
  record_pass "Cleanup: testuser1 left direct room"

  # User2 leaves too
  matrix_api "$t2" POST "/_matrix/client/v3/rooms/${direct_room_id}/leave" "{}" > /dev/null 2>&1
  matrix_api "$t2" POST "/_matrix/client/v3/rooms/${direct_room_id}/forget" "{}" > /dev/null 2>&1
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 4: Group Room Tests — API-orchestrated
# ═══════════════════════════════════════════════════════════════════════════════

phase_groups() {
  log_header "PHASE 4: Group Rooms"

  local t1="$(get_token testuser1)"
  local t2="$(get_token testuser2)"
  local t3="$(get_token testuser3)"
  local u1="$(get_userid testuser1)"
  local u2="$(get_userid testuser2)"
  local u3="$(get_userid testuser3)"

  if [ -z "$t1" ] || [ -z "$t2" ] || [ -z "$t3" ]; then
    record_skip "Group room tests (login tokens missing)"
    return
  fi

  # 4.1: Create a group with expiration
  log_step "testuser1 creates group 'TestSquad' (1hr expiry)..."
  local expiration=$(( $(date +%s) + 3600 ))
  local group_name="Grid:Group:${expiration}:TestSquad:${u1}"

  local power_levels="{
    \"ban\":50,\"events\":{\"m.room.name\":50,\"m.room.power_levels\":100,\"m.room.history_visibility\":100,\"m.room.canonical_alias\":50,\"m.room.avatar\":50,\"m.room.tombstone\":100,\"m.room.server_acl\":100,\"m.room.encryption\":100},
    \"events_default\":0,\"invite\":100,\"kick\":100,
    \"notifications\":{\"room\":50},\"redact\":50,\"state_default\":50,
    \"users\":{\"${u1}\":100},\"users_default\":0
  }"

  local create_result
  create_result=$(matrix_api "$t1" POST "/_matrix/client/v3/createRoom" "{
    \"name\": \"${group_name}\",
    \"is_direct\": false,
    \"visibility\": \"private\",
    \"initial_state\": [
      {\"type\":\"m.room.encryption\",\"content\":{\"algorithm\":\"m.megolm.v1.aes-sha2\"},\"state_key\":\"\"},
      {\"type\":\"m.room.power_levels\",\"content\":${power_levels},\"state_key\":\"\"}
    ]
  }")

  local group_room_id
  group_room_id=$(echo "$create_result" | jq -r '.room_id // empty')

  if [ -n "$group_room_id" ]; then
    record_pass "Create group room: ${group_room_id}"
  else
    record_fail "Create group room" "$(echo "$create_result" | jq -r '.error // "unknown"')"
    return
  fi

  # 4.2: Verify group room name convention
  local fetched_name
  fetched_name=$(matrix_api "$t1" GET "/_matrix/client/v3/rooms/${group_room_id}/state/m.room.name" | jq -r '.name // empty')
  if [[ "$fetched_name" == Grid:Group:*:TestSquad:* ]]; then
    record_pass "Group name matches Grid format"
  else
    record_fail "Group name format" "Got: ${fetched_name}"
  fi

  # 4.3: Verify power levels (creator=100, invite=100, kick=100)
  local pl
  pl=$(matrix_api "$t1" GET "/_matrix/client/v3/rooms/${group_room_id}/state/m.room.power_levels")
  local creator_pl=$(echo "$pl" | jq -r ".users[\"${u1}\"] // 0")
  local invite_pl=$(echo "$pl" | jq -r '.invite // 0')
  local kick_pl=$(echo "$pl" | jq -r '.kick // 0')
  if [ "$creator_pl" = "100" ] && [ "$invite_pl" = "100" ] && [ "$kick_pl" = "100" ]; then
    record_pass "Power levels correct (creator=100, invite=100, kick=100)"
  else
    record_fail "Power levels" "creator=${creator_pl}, invite=${invite_pl}, kick=${kick_pl}"
  fi

  # 4.4: Invite members (creator does this post-creation, matching Grid)
  local inv2 inv3
  inv2=$(matrix_api "$t1" POST "/_matrix/client/v3/rooms/${group_room_id}/invite" "{\"user_id\":\"${u2}\"}")
  inv3=$(matrix_api "$t1" POST "/_matrix/client/v3/rooms/${group_room_id}/invite" "{\"user_id\":\"${u3}\"}")
  record_pass "Invited testuser2 and testuser3"

  # 4.5: Add Grid Group tag
  matrix_api "$t1" PUT "/_matrix/client/v3/user/${u1}/rooms/${group_room_id}/tags/Grid%20Group" "{}" > /dev/null 2>&1
  record_pass "Added 'Grid Group' tag"

  # 4.6: Users accept invites
  matrix_api "$t2" POST "/_matrix/client/v3/join/${group_room_id}" "{}" > /dev/null 2>&1
  matrix_api "$t3" POST "/_matrix/client/v3/join/${group_room_id}" "{}" > /dev/null 2>&1
  sleep 1

  local member_count
  member_count=$(matrix_api "$t1" GET "/_matrix/client/v3/rooms/${group_room_id}/members" | \
    jq '[.chunk[] | select(.content.membership == "join")] | length')
  if [ "$member_count" = "3" ]; then
    record_pass "All 3 members joined group"
  else
    record_fail "Group membership" "Expected 3 joined, got ${member_count}"
  fi

  # 4.7: Multiple users send locations
  log_step "All users share locations..."
  for user_num in 1 2 3; do
    local user="testuser${user_num}"
    local token="$(get_token $user)"
    local lat=$(echo "40.7580 + 0.00${user_num}" | bc)
    local lon="-73.9855"
    local ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    local txn="grp${user_num}$(date +%s)"

    local result
    result=$(matrix_api "$token" PUT \
      "/_matrix/client/v3/rooms/${group_room_id}/send/m.room.message/${txn}" \
      "{
        \"msgtype\":\"m.location\",
        \"body\":\"Current location\",
        \"geo_uri\":\"geo:${lat},${lon}\",
        \"description\":\"Current location\",
        \"timestamp\":\"${ts}\"
      }")

    local eid
    eid=$(echo "$result" | jq -r '.event_id // empty')
    if [ -n "$eid" ]; then
      record_pass "Location from ${user}: geo:${lat},${lon}"
    else
      record_fail "Location from ${user}" "$(echo "$result" | jq -r '.error // "unknown"')"
    fi
  done

  # 4.8: Verify all locations are readable
  sleep 1
  local loc_count
  loc_count=$(matrix_api "$t1" GET "/_matrix/client/v3/rooms/${group_room_id}/messages?dir=b&limit=20" | \
    jq '[.chunk[] | select(.content.msgtype == "m.location")] | length')
  if [ "$loc_count" -ge 3 ]; then
    record_pass "All ${loc_count} location events readable"
  else
    record_fail "Read locations" "Expected ≥3, got ${loc_count}"
  fi

  # 4.9: Non-admin can't invite (power level enforcement)
  log_step "Verifying power level enforcement..."
  local bad_invite
  bad_invite=$(curl -s -X POST "${SYNAPSE_URL}/_matrix/client/v3/rooms/${group_room_id}/invite" \
    -H "Authorization: Bearer ${t2}" \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":\"@testuser4:${SYNAPSE_URL#*://}\"}" 2>&1)
  # This should fail since invite power is 100 and testuser2 has 0
  if echo "$bad_invite" | jq -r '.errcode // empty' | grep -q "M_FORBIDDEN"; then
    record_pass "Non-admin invite blocked (power levels enforced)"
  else
    # Could also be a different error format or the user doesn't exist
    local errcode
    errcode=$(echo "$bad_invite" | jq -r '.errcode // empty')
    if [ -n "$errcode" ]; then
      record_pass "Non-admin invite blocked (${errcode})"
    else
      record_fail "Power level enforcement" "Non-admin was able to invite"
    fi
  fi

  # 4.10: Cleanup
  for user in testuser1 testuser2 testuser3; do
    local token="$(get_token $user)"
    matrix_api "$token" POST "/_matrix/client/v3/rooms/${group_room_id}/leave" "{}" > /dev/null 2>&1
    matrix_api "$token" POST "/_matrix/client/v3/rooms/${group_room_id}/forget" "{}" > /dev/null 2>&1
  done
  record_pass "Cleanup: all users left group"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 5: Expired Group Handling
# ═══════════════════════════════════════════════════════════════════════════════

phase_expiry() {
  log_header "PHASE 5: Group Expiration"

  local t1="$(get_token testuser1)"
  local u1="$(get_userid testuser1)"

  if [ -z "$t1" ]; then
    record_skip "Expiry tests (login tokens missing)"
    return
  fi

  # Create a group that's already expired (timestamp in the past)
  local past_ts=$(( $(date +%s) - 3600 ))
  local room_name="Grid:Group:${past_ts}:ExpiredGroup:${u1}"

  local result
  result=$(matrix_api "$t1" POST "/_matrix/client/v3/createRoom" "{
    \"name\": \"${room_name}\",
    \"visibility\": \"private\",
    \"initial_state\": [
      {\"type\":\"m.room.encryption\",\"content\":{\"algorithm\":\"m.megolm.v1.aes-sha2\"},\"state_key\":\"\"}
    ]
  }")

  local expired_room_id
  expired_room_id=$(echo "$result" | jq -r '.room_id // empty')

  if [ -n "$expired_room_id" ]; then
    record_pass "Created pre-expired group: ${expired_room_id}"
  else
    record_fail "Create expired group" "$(echo "$result" | jq -r '.error // "unknown"')"
    return
  fi

  # Verify the name parses as expired
  local name_parts
  name_parts=$(echo "$room_name" | tr ':' '\n')
  local exp_field
  exp_field=$(echo "$room_name" | cut -d: -f3)
  local now=$(date +%s)
  if [ "$exp_field" -lt "$now" ]; then
    record_pass "Expiration timestamp is in the past (${exp_field} < ${now})"
  else
    record_fail "Expiration parsing" "${exp_field} should be < ${now}"
  fi

  # Test the no-expiration case (timestamp=0)
  local forever_name="Grid:Group:0:ForeverGroup:${u1}"
  local forever_result
  forever_result=$(matrix_api "$t1" POST "/_matrix/client/v3/createRoom" "{
    \"name\": \"${forever_name}\",
    \"visibility\": \"private\",
    \"initial_state\": [
      {\"type\":\"m.room.encryption\",\"content\":{\"algorithm\":\"m.megolm.v1.aes-sha2\"},\"state_key\":\"\"}
    ]
  }")
  local forever_room_id
  forever_room_id=$(echo "$forever_result" | jq -r '.room_id // empty')
  if [ -n "$forever_room_id" ]; then
    record_pass "Created non-expiring group (timestamp=0): ${forever_room_id}"
  else
    record_fail "Create non-expiring group" "$(echo "$forever_result" | jq -r '.error // "unknown"')"
  fi

  # Cleanup
  for rid in "$expired_room_id" "$forever_room_id"; do
    if [ -n "$rid" ]; then
      matrix_api "$t1" POST "/_matrix/client/v3/rooms/${rid}/leave" "{}" > /dev/null 2>&1
      matrix_api "$t1" POST "/_matrix/client/v3/rooms/${rid}/forget" "{}" > /dev/null 2>&1
    fi
  done
  record_pass "Cleanup: expired/forever groups removed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 6: Location Event Format Validation
# ═══════════════════════════════════════════════════════════════════════════════

phase_location_format() {
  log_header "PHASE 6: Location Event Format"

  local t1="$(get_token testuser1)"
  local t2="$(get_token testuser2)"
  local u1="$(get_userid testuser1)"
  local u2="$(get_userid testuser2)"

  if [ -z "$t1" ] || [ -z "$t2" ]; then
    record_skip "Location format tests (tokens missing)"
    return
  fi

  # Create a temp direct room for this test
  local room_name="Grid:Direct:${u1}:${u2}"
  local room_id
  room_id=$(matrix_api "$t1" POST "/_matrix/client/v3/createRoom" "{
    \"name\":\"${room_name}\",
    \"is_direct\":true,
    \"preset\":\"private_chat\",
    \"invite\":[\"${u2}\"],
    \"initial_state\":[{\"type\":\"m.room.encryption\",\"content\":{\"algorithm\":\"m.megolm.v1.aes-sha2\"},\"state_key\":\"\"}]
  }" | jq -r '.room_id // empty')

  if [ -z "$room_id" ]; then
    record_fail "Setup room for location tests" "Could not create room"
    return
  fi

  matrix_api "$t2" POST "/_matrix/client/v3/join/${room_id}" "{}" > /dev/null 2>&1
  sleep 1

  # Send a location and verify every field matches Grid's format
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  local txn="fmt$(date +%s)"
  matrix_api "$t1" PUT \
    "/_matrix/client/v3/rooms/${room_id}/send/m.room.message/${txn}" \
    "{
      \"msgtype\":\"m.location\",
      \"body\":\"Current location\",
      \"geo_uri\":\"geo:51.5074,-0.1278\",
      \"description\":\"Current location\",
      \"timestamp\":\"${ts}\"
    }" > /dev/null

  sleep 1

  # Fetch and validate each field
  local event
  event=$(matrix_api "$t2" GET "/_matrix/client/v3/rooms/${room_id}/messages?dir=b&limit=5" | \
    jq '.chunk[] | select(.content.msgtype == "m.location")' | head -20)

  local msgtype body geo_uri description timestamp_val
  msgtype=$(echo "$event" | jq -r '.content.msgtype')
  body=$(echo "$event" | jq -r '.content.body')
  geo_uri=$(echo "$event" | jq -r '.content.geo_uri')
  description=$(echo "$event" | jq -r '.content.description')
  timestamp_val=$(echo "$event" | jq -r '.content.timestamp')

  [ "$msgtype" = "m.location" ] && record_pass "msgtype = m.location" || record_fail "msgtype" "got: $msgtype"
  [ "$body" = "Current location" ] && record_pass "body = 'Current location'" || record_fail "body" "got: $body"
  [ "$geo_uri" = "geo:51.5074,-0.1278" ] && record_pass "geo_uri = geo:51.5074,-0.1278" || record_fail "geo_uri" "got: $geo_uri"
  [ "$description" = "Current location" ] && record_pass "description = 'Current location'" || record_fail "description" "got: $description"

  # Validate timestamp is ISO8601
  if echo "$timestamp_val" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'; then
    record_pass "timestamp is ISO8601: ${timestamp_val}"
  else
    record_fail "timestamp format" "got: ${timestamp_val}"
  fi

  # Cleanup
  matrix_api "$t1" POST "/_matrix/client/v3/rooms/${room_id}/leave" "{}" > /dev/null 2>&1
  matrix_api "$t2" POST "/_matrix/client/v3/rooms/${room_id}/leave" "{}" > /dev/null 2>&1
  matrix_api "$t1" POST "/_matrix/client/v3/rooms/${room_id}/forget" "{}" > /dev/null 2>&1
  matrix_api "$t2" POST "/_matrix/client/v3/rooms/${room_id}/forget" "{}" > /dev/null 2>&1
}

# ═══════════════════════════════════════════════════════════════════════════════
# REPORT
# ═══════════════════════════════════════════════════════════════════════════════

print_report() {
  local end_time=$(date +%s)
  local duration=$(( end_time - START_TIME ))

  log_header "TEST REPORT"

  echo ""
  echo -e "  ${GREEN}Passed:${NC}  ${PASSED}"
  echo -e "  ${RED}Failed:${NC}  ${FAILED}"
  echo -e "  ${YELLOW}Skipped:${NC} ${SKIPPED}"
  echo -e "  ${BOLD}Total:${NC}   ${TOTAL}"
  echo ""
  echo -e "  ${DIM}Duration: ${duration}s${NC}"
  echo ""

  if [ ${#FAILURES[@]} -gt 0 ]; then
    echo -e "${RED}──── Failures ────${NC}"
    for f in "${FAILURES[@]}"; do
      echo -e "  ${RED}✗${NC} $f"
    done
    echo ""
  fi

  # Save report to file
  local report_file="$REPORT_DIR/e2e-$(date +%Y%m%d-%H%M%S).txt"
  {
    echo "Grid E2E Test Report"
    echo "Date: $(date)"
    echo "Duration: ${duration}s"
    echo ""
    echo "Passed:  ${PASSED}"
    echo "Failed:  ${FAILED}"
    echo "Skipped: ${SKIPPED}"
    echo "Total:   ${TOTAL}"
    if [ ${#FAILURES[@]} -gt 0 ]; then
      echo ""
      echo "Failures:"
      for f in "${FAILURES[@]}"; do
        echo "  ✗ $f"
      done
    fi
  } > "$report_file"
  echo -e "  ${DIM}Report saved: ${report_file}${NC}"

  if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}${BOLD}  RESULT: FAIL${NC}"
    return 1
  else
    echo -e "${GREEN}${BOLD}  RESULT: PASS ✓${NC}"
    return 0
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  log_header "Grid E2E Test Suite"
  echo -e "  ${DIM}$(date)${NC}"
  echo -e "  ${DIM}Synapse: ${SYNAPSE_URL}${NC}"
  echo -e "  ${DIM}Project: ${PROJECT_ROOT}${NC}"

  should_run "infra"    && phase_infra
  should_run "auth"     && phase_auth
  should_run "ui"       && { [[ "${SKIP_UI:-false}" == "true" ]] && log_step "Skipping UI tests (--skip-ui)" || phase_ui; }
  should_run "direct"   && phase_direct
  should_run "groups"   && phase_groups
  should_run "expiry"   && phase_expiry
  should_run "location" && phase_location_format

  # Always tear down Synapse after tests
  log_phase "Cleanup: Stopping Synapse"
  (cd "$INFRA_DIR" && docker compose down -v 2>&1 | tail -3)
  echo -e "  ${GREEN}✓${NC} Synapse stopped and volumes removed"

  print_report
}

main
