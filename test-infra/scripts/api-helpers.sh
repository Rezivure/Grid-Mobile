#!/bin/bash
# api-helpers.sh — Setup helper functions for multi-user E2E tests
# These functions prepare API state for Maestro UI verification

source "$(dirname "$0")/grid-api.sh"

SYNAPSE_URL="${SYNAPSE_URL:-http://localhost:8008}"

# ─── Helper: Login as different user ───────────────────────────────────────────

login_as_user() {
  local user="$1"
  local password="${2:-testpass123}"
  
  echo "🔄 Logging in as $user..."
  if grid_login "$user" "$password"; then
    echo "✓ Logged in as $user"
    return 0
  else
    echo "✗ Failed to login as $user"
    return 1
  fi
}

# ─── API Setup Functions ───────────────────────────────────────────────────────

# Setup: testuser2 creates direct room and sends location to testuser1  
setup_incoming_location() {
  local lat="${1:-40.7580}"    # NYC coordinates by default
  local lon="${2:--73.9855}"
  
  echo "🚀 Setting up incoming location from testuser2 to testuser1..."
  
  # Login as testuser2
  login_as_user "testuser2" || return 1
  
  # Create direct room with testuser1
  echo "Creating direct room..."
  local room_id
  room_id=$(grid_create_direct "testuser1")
  if [ -z "$room_id" ]; then
    echo "✗ Failed to create direct room"
    return 1
  fi
  
  # Send location
  echo "Sending location: $lat, $lon"
  if grid_send_location "$room_id" "$lat" "$lon"; then
    echo "✓ Location sent successfully"
    echo "ROOM_ID: $room_id"
    return 0
  else
    echo "✗ Failed to send location"
    return 1
  fi
}

# Setup: testuser2 sends friend request to testuser1 (creates notification badge)
setup_friend_request_notification() {
  echo "🚀 Setting up friend request notification from testuser2 to testuser1..."
  
  # Login as testuser2  
  login_as_user "testuser2" || return 1
  
  # Create direct room (this sends the friend request)
  local room_id
  room_id=$(grid_create_direct "testuser1")
  if [ -n "$room_id" ]; then
    echo "✓ Friend request sent successfully"
    echo "ROOM_ID: $room_id"
    return 0
  else
    echo "✗ Failed to send friend request"
    return 1
  fi
}

# Setup: testuser2 creates group and invites testuser1
setup_group_invite() {
  local group_name="${1:-Test Pizza Party}"
  local duration="${2:-3600}"
  
  echo "🚀 Setting up group invite: '$group_name' from testuser2..."
  
  # Login as testuser2
  login_as_user "testuser2" || return 1
  
  # Create group and invite testuser1
  local room_id
  room_id=$(grid_create_group "$group_name" "$duration" "testuser1")
  if [ -n "$room_id" ]; then
    echo "✓ Group created and invite sent"
    echo "ROOM_ID: $room_id"
    echo "$room_id" > /tmp/test_group_room_id  # Save for later use
    return 0
  else
    echo "✗ Failed to create group"
    return 1
  fi
}

# Setup: Create group, testuser1 joins, then testuser2 leaves
setup_group_member_leaves() {
  local group_name="${1:-Test Abandonment Group}"
  
  echo "🚀 Setting up group where member leaves..."
  
  # testuser2 creates group
  login_as_user "testuser2" || return 1
  local room_id
  room_id=$(grid_create_group "$group_name" "0" "testuser1")
  [ -z "$room_id" ] && { echo "✗ Failed to create group"; return 1; }
  
  # testuser1 joins
  login_as_user "testuser1" || return 1
  grid_accept_invite "$room_id" || { echo "✗ testuser1 failed to join"; return 1; }
  
  # testuser2 leaves  
  login_as_user "testuser2" || return 1
  grid_leave_room "$room_id"
  
  echo "✓ Group setup complete, testuser2 left"
  echo "ROOM_ID: $room_id"
  echo "$room_id" > /tmp/test_group_room_id
  return 0
}

# Setup: testuser2 sets avatar URL
setup_avatar_update() {
  local avatar_url="${1:-mxc://localhost/testuser2-avatar-123}"
  
  echo "🚀 Setting up avatar update for testuser2..."
  
  # Login as testuser2
  login_as_user "testuser2" || return 1
  
  # Set avatar
  if grid_set_avatar "$avatar_url"; then
    echo "✓ Avatar set successfully"
    return 0
  else
    echo "✗ Failed to set avatar"
    return 1
  fi
}

# Setup: Send multiple friend requests to testuser1
setup_multiple_friend_requests() {
  local count="${1:-3}"
  
  echo "🚀 Setting up $count friend requests to testuser1..."
  
  local success_count=0
  for i in $(seq 2 $((count + 1))); do
    local user="testuser$i"
    echo "Sending friend request from $user..."
    
    if login_as_user "$user"; then
      local room_id
      room_id=$(grid_create_direct "testuser1")
      if [ -n "$room_id" ]; then
        echo "  ✓ Request sent from $user"
        ((success_count++))
      else
        echo "  ✗ Failed to send from $user"
      fi
    fi
  done
  
  echo "✓ Sent $success_count out of $count friend requests"
  return 0
}

# Setup: testuser2 sends multiple location updates (creates trail)
setup_location_trail() {
  local room_id="$1"
  
  if [ -z "$room_id" ]; then
    # Create room first
    echo "🚀 Creating room for location trail..."
    login_as_user "testuser2" || return 1
    room_id=$(grid_create_direct "testuser1")
    [ -z "$room_id" ] && { echo "✗ Failed to create room"; return 1; }
  fi
  
  echo "🚀 Setting up location trail from testuser2..."
  login_as_user "testuser2" || return 1
  
  # Send sequence of locations (simulating movement through NYC)
  local locations=(
    "40.7580 -73.9855"  # Times Square
    "40.7614 -73.9776"  # Central Park South
    "40.7829 -73.9654"  # Central Park North
    "40.7589 -73.9851"  # Times Square North
  )
  
  for location in "${locations[@]}"; do
    local lat lon
    lat=$(echo $location | cut -d' ' -f1)
    lon=$(echo $location | cut -d' ' -f2)
    
    echo "Sending location: $lat, $lon"
    grid_send_location "$room_id" "$lat" "$lon"
    sleep 1  # Small delay between updates
  done
  
  echo "✓ Location trail sent successfully"
  echo "ROOM_ID: $room_id"
  return 0
}

# Setup: testuser2 stops sharing location (goes incognito)
setup_contact_incognito() {
  echo "🚀 Setting up testuser2 going incognito..."
  
  # Login as testuser2
  login_as_user "testuser2" || return 1
  
  # Create direct room first (to establish contact)
  local room_id
  room_id=$(grid_create_direct "testuser1")
  [ -z "$room_id" ] && { echo "✗ Failed to create room"; return 1; }
  
  # Send location initially
  echo "Sending initial location..."
  grid_send_location "$room_id" "40.7580" "-73.9855"
  
  # Simulate going incognito by leaving the room
  echo "testuser2 going incognito (leaving room)..."
  grid_leave_room "$room_id"
  
  echo "✓ testuser2 is now incognito"
  echo "ROOM_ID: $room_id"  
  return 0
}

# Cleanup: Reset test state
cleanup_test_state() {
  echo "🧹 Cleaning up test state..."
  
  # Login as testuser1 and leave all rooms
  if login_as_user "testuser1"; then
    local invites
    invites=$(grid_get_invites)
    for room_id in $invites; do
      echo "  Declining invite: $room_id"
      grid_decline_invite "$room_id"
    done
  fi
  
  # Clean up testuser2-5 states
  for i in 2 3 4 5; do
    if login_as_user "testuser$i"; then
      local invites
      invites=$(grid_get_invites)
      for room_id in $invites; do
        echo "  testuser$i declining: $room_id"
        grid_decline_invite "$room_id"
      done
    fi
  done
  
  echo "✓ Cleanup complete"
}

# Utility: Wait for sync to propagate
wait_for_sync() {
  local seconds="${1:-3}"
  echo "⏳ Waiting ${seconds}s for sync to propagate..."
  sleep "$seconds"
}

echo "API Helpers loaded. Functions available:"
echo "  setup_incoming_location [lat] [lon]"
echo "  setup_friend_request_notification"
echo "  setup_group_invite [name] [duration]"  
echo "  setup_group_member_leaves [name]"
echo "  setup_avatar_update [avatar_url]"
echo "  setup_multiple_friend_requests [count]"
echo "  setup_location_trail [room_id]"
echo "  setup_contact_incognito"
echo "  cleanup_test_state"
echo "  wait_for_sync [seconds]"