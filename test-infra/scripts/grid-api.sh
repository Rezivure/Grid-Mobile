#!/bin/bash
# grid-api.sh — Grid-compatible Matrix API helper for test orchestration
# Emulates exactly what Grid's Flutter app does via the Matrix SDK.
#
# Usage:
#   source grid-api.sh
#   grid_login testuser1 testpass123
#   grid_create_direct testuser2
#   grid_accept_invite <room_id>
#   grid_send_location <room_id> 40.7580 -73.9855
#   grid_create_group "Pizza Night" 3600 testuser2 testuser3
#   grid_get_invites
#   grid_sync

SYNAPSE_URL="${SYNAPSE_URL:-http://localhost:8008}"

# State (per-sourced-shell)
GRID_ACCESS_TOKEN=""
GRID_USER_ID=""
GRID_HOMESERVER=""
GRID_SINCE=""

# ─── Auth ───────────────────────────────────────────────────────────────────────

grid_login() {
  local username="$1"
  local password="${2:-testpass123}"

  local result
  result=$(curl -s -X POST "${SYNAPSE_URL}/_matrix/client/v3/login" \
    -H "Content-Type: application/json" \
    -d "{
      \"type\": \"m.login.password\",
      \"identifier\": {\"type\": \"m.id.user\", \"user\": \"${username}\"},
      \"password\": \"${password}\"
    }")

  GRID_ACCESS_TOKEN=$(echo "$result" | jq -r '.access_token // empty')
  GRID_USER_ID=$(echo "$result" | jq -r '.user_id // empty')
  GRID_HOMESERVER=$(echo "$SYNAPSE_URL" | sed 's|https\?://||')

  if [ -z "$GRID_ACCESS_TOKEN" ]; then
    echo "✗ Login failed for ${username}: $(echo "$result" | jq -r '.error // "unknown"')"
    return 1
  fi

  echo "✓ Logged in as ${GRID_USER_ID} (token: ${GRID_ACCESS_TOKEN:0:12}...)"
  return 0
}

# ─── Helpers ────────────────────────────────────────────────────────────────────

_matrix_api() {
  local method="$1"
  local endpoint="$2"
  local data="$3"

  if [ -n "$data" ]; then
    curl -s -X "$method" "${SYNAPSE_URL}${endpoint}" \
      -H "Authorization: Bearer ${GRID_ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -s -X "$method" "${SYNAPSE_URL}${endpoint}" \
      -H "Authorization: Bearer ${GRID_ACCESS_TOKEN}"
  fi
}

_full_user_id() {
  local user="$1"
  # If already a full Matrix ID, return as-is
  if [[ "$user" == @* ]]; then
    echo "$user"
  else
    echo "@${user}:${GRID_HOMESERVER}"
  fi
}

# ─── Direct Room (Contact Invite) ──────────────────────────────────────────────
# Emulates RoomService.createRoomAndInviteContact
# Room name format: Grid:Direct:<myUserId>:<targetUserId>

grid_create_direct() {
  local target_user="$1"
  local target_full=$(_full_user_id "$target_user")
  local room_name="Grid:Direct:${GRID_USER_ID}:${target_full}"

  local result
  result=$(_matrix_api POST "/_matrix/client/v3/createRoom" "{
    \"name\": \"${room_name}\",
    \"is_direct\": true,
    \"preset\": \"private_chat\",
    \"invite\": [\"${target_full}\"],
    \"initial_state\": [
      {
        \"type\": \"m.room.encryption\",
        \"content\": {\"algorithm\": \"m.megolm.v1.aes-sha2\"},
        \"state_key\": \"\"
      }
    ]
  }")

  local room_id
  room_id=$(echo "$result" | jq -r '.room_id // empty')

  if [ -z "$room_id" ]; then
    echo "✗ Failed to create direct room: $(echo "$result" | jq -r '.error // "unknown"')"
    return 1
  fi

  echo "✓ Direct room created: ${room_id} (${room_name})"
  echo "$room_id"
  return 0
}

# ─── Group Room ─────────────────────────────────────────────────────────────────
# Emulates RoomService.createGroup
# Room name format: Grid:Group:<expirationTimestamp>:<groupName>:<creatorUserId>
# durationSeconds=0 means no expiration

grid_create_group() {
  local group_name="$1"
  local duration_seconds="${2:-0}"
  shift 2
  local members=("$@")

  local expiration_timestamp=0
  if [ "$duration_seconds" -gt 0 ]; then
    expiration_timestamp=$(( $(date +%s) + duration_seconds ))
  fi

  local room_name="Grid:Group:${expiration_timestamp}:${group_name}:${GRID_USER_ID}"

  # Build invite list
  local invite_json="["
  local first=true
  for member in "${members[@]}"; do
    local full_id=$(_full_user_id "$member")
    if [ "$first" = true ]; then
      invite_json+="\"${full_id}\""
      first=false
    else
      invite_json+=",\"${full_id}\""
    fi
  done
  invite_json+="]"

  # Power levels matching Grid's createGroup exactly
  local power_levels="{
    \"ban\": 50,
    \"events\": {
      \"m.room.name\": 50,
      \"m.room.power_levels\": 100,
      \"m.room.history_visibility\": 100,
      \"m.room.canonical_alias\": 50,
      \"m.room.avatar\": 50,
      \"m.room.tombstone\": 100,
      \"m.room.server_acl\": 100,
      \"m.room.encryption\": 100
    },
    \"events_default\": 0,
    \"invite\": 100,
    \"kick\": 100,
    \"notifications\": {\"room\": 50},
    \"redact\": 50,
    \"state_default\": 50,
    \"users\": {\"${GRID_USER_ID}\": 100},
    \"users_default\": 0
  }"

  local result
  result=$(_matrix_api POST "/_matrix/client/v3/createRoom" "{
    \"name\": \"${room_name}\",
    \"is_direct\": false,
    \"visibility\": \"private\",
    \"initial_state\": [
      {
        \"type\": \"m.room.encryption\",
        \"content\": {\"algorithm\": \"m.megolm.v1.aes-sha2\"},
        \"state_key\": \"\"
      },
      {
        \"type\": \"m.room.power_levels\",
        \"content\": ${power_levels},
        \"state_key\": \"\"
      }
    ]
  }")

  local room_id
  room_id=$(echo "$result" | jq -r '.room_id // empty')

  if [ -z "$room_id" ]; then
    echo "✗ Failed to create group: $(echo "$result" | jq -r '.error // "unknown"')"
    return 1
  fi

  # Invite members (Grid does this after room creation, not in createRoom)
  for member in "${members[@]}"; do
    local full_id=$(_full_user_id "$member")
    local invite_result
    invite_result=$(_matrix_api POST "/_matrix/client/v3/rooms/${room_id}/invite" \
      "{\"user_id\": \"${full_id}\"}")
    echo "  Invited ${full_id}"
  done

  # Add tag (Grid tags groups with "Grid Group")
  _matrix_api PUT "/_matrix/client/v3/user/${GRID_USER_ID}/rooms/${room_id}/tags/Grid%20Group" \
    "{}" > /dev/null

  echo "✓ Group created: ${room_id} (${room_name})"
  echo "$room_id"
  return 0
}

# ─── Accept Invite ──────────────────────────────────────────────────────────────
# Emulates RoomService.acceptInvitation

grid_accept_invite() {
  local room_id="$1"

  local result
  result=$(_matrix_api POST "/_matrix/client/v3/join/${room_id}" "{}")

  local joined_room
  joined_room=$(echo "$result" | jq -r '.room_id // empty')

  if [ -z "$joined_room" ]; then
    echo "✗ Failed to join ${room_id}: $(echo "$result" | jq -r '.error // "unknown"')"
    return 1
  fi

  echo "✓ Joined room: ${joined_room}"
  return 0
}

# ─── Decline Invite ─────────────────────────────────────────────────────────────

grid_decline_invite() {
  local room_id="$1"
  _matrix_api POST "/_matrix/client/v3/rooms/${room_id}/leave" "{}" > /dev/null
  echo "✓ Declined invite for ${room_id}"
}

# ─── Send Location ──────────────────────────────────────────────────────────────
# Emulates RoomService.sendLocationEvent
# Event content matches Grid exactly: msgtype=m.location, geo_uri, timestamp

grid_send_location() {
  local room_id="$1"
  local latitude="$2"
  local longitude="$3"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

  local txn_id
  txn_id="m$(date +%s%N)"

  local result
  result=$(_matrix_api PUT \
    "/_matrix/client/v3/rooms/${room_id}/send/m.room.message/${txn_id}" \
    "{
      \"msgtype\": \"m.location\",
      \"body\": \"Current location\",
      \"geo_uri\": \"geo:${latitude},${longitude}\",
      \"description\": \"Current location\",
      \"timestamp\": \"${timestamp}\"
    }")

  local event_id
  event_id=$(echo "$result" | jq -r '.event_id // empty')

  if [ -z "$event_id" ]; then
    echo "✗ Failed to send location: $(echo "$result" | jq -r '.error // "unknown"')"
    return 1
  fi

  echo "✓ Location sent to ${room_id}: geo:${latitude},${longitude} (${event_id})"
  return 0
}

# ─── Get Pending Invites ────────────────────────────────────────────────────────

grid_get_invites() {
  local result
  result=$(_matrix_api GET "/_matrix/client/v3/sync?filter={\"room\":{\"timeline\":{\"limit\":0}}}")

  echo "$result" | jq -r '.rooms.invite // {} | keys[]' 2>/dev/null
}

# ─── Sync (get latest state) ────────────────────────────────────────────────────

grid_sync() {
  local filter='{"room":{"timeline":{"limit":5}}}'
  local url="/_matrix/client/v3/sync?filter=$(echo "$filter" | jq -sRr @uri)"

  if [ -n "$GRID_SINCE" ]; then
    url="${url}&since=${GRID_SINCE}"
  fi

  local result
  result=$(_matrix_api GET "$url")

  GRID_SINCE=$(echo "$result" | jq -r '.next_batch // empty')

  echo "$result"
}

# ─── Leave Room ─────────────────────────────────────────────────────────────────

grid_leave_room() {
  local room_id="$1"
  _matrix_api POST "/_matrix/client/v3/rooms/${room_id}/leave" "{}" > /dev/null
  _matrix_api POST "/_matrix/client/v3/rooms/${room_id}/forget" "{}" > /dev/null
  echo "✓ Left and forgot room: ${room_id}"
}

# ─── Get Room Members ───────────────────────────────────────────────────────────

grid_get_members() {
  local room_id="$1"
  _matrix_api GET "/_matrix/client/v3/rooms/${room_id}/members" | \
    jq -r '.chunk[] | "\(.state_key) (\(.content.membership))"'
}

# ─── Get Room Messages (Location Events) ────────────────────────────────────────

grid_get_locations() {
  local room_id="$1"
  local limit="${2:-10}"

  _matrix_api GET "/_matrix/client/v3/rooms/${room_id}/messages?dir=b&limit=${limit}" | \
    jq -r '.chunk[] | select(.content.msgtype == "m.location") |
      "\(.sender) @ \(.content.timestamp): \(.content.geo_uri)"'
}

# ─── User Profile ───────────────────────────────────────────────────────────────

grid_set_displayname() {
  local displayname="$1"
  _matrix_api PUT "/_matrix/client/v3/profile/${GRID_USER_ID}/displayname" \
    "{\"displayname\": \"${displayname}\"}" > /dev/null
  echo "✓ Display name set to: ${displayname}"
}

# ─── Print current state ────────────────────────────────────────────────────────

grid_whoami() {
  echo "User:      ${GRID_USER_ID}"
  echo "Server:    ${GRID_HOMESERVER}"
  echo "Token:     ${GRID_ACCESS_TOKEN:0:16}..."
}

echo "Grid Test API loaded. Functions available:"
echo "  grid_login <user> [password]"
echo "  grid_create_direct <target_user>"
echo "  grid_create_group <name> <duration_secs> <user1> [user2] ..."
echo "  grid_accept_invite <room_id>"
echo "  grid_decline_invite <room_id>"
echo "  grid_send_location <room_id> <lat> <lon>"
echo "  grid_get_invites"
echo "  grid_get_members <room_id>"
echo "  grid_get_locations <room_id> [limit]"
echo "  grid_leave_room <room_id>"
echo "  grid_set_displayname <name>"
echo "  grid_sync"
echo "  grid_whoami"
