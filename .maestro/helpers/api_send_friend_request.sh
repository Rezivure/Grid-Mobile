#!/bin/bash

# Send friend request from one user to another by creating DM room and inviting
# Usage: api_send_friend_request.sh <from_user> <to_user>

if [ $# -ne 2 ]; then
    echo "Usage: $0 <from_user> <to_user>"
    exit 1
fi

FROM_USER=$1
TO_USER=$2
HOMESERVER="http://localhost:8008"

# Get access token for sender
ACCESS_TOKEN=$(./api_login.sh "$FROM_USER")
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to get access token for $FROM_USER" >&2
    exit 1
fi

# Create DM room
ROOM_DATA=$(curl -s -X POST "$HOMESERVER/_matrix/client/r0/createRoom" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"is_direct\":true,\"preset\":\"trusted_private_chat\"}")

ROOM_ID=$(echo "$ROOM_DATA" | jq -r '.room_id')

if [ "$ROOM_ID" = "null" ] || [ -z "$ROOM_ID" ]; then
    echo "ERROR: Failed to create room" >&2
    echo "$ROOM_DATA" >&2
    exit 1
fi

# Invite the target user
INVITE_RESULT=$(curl -s -X POST "$HOMESERVER/_matrix/client/r0/rooms/$ROOM_ID/invite" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":\"@$TO_USER:localhost\"}")

echo "Friend request sent from $FROM_USER to $TO_USER (Room: $ROOM_ID)"