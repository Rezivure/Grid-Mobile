#!/bin/bash

# Join a room (accept invite)
# Usage: api_join_room.sh <user> <room_id>

if [ $# -ne 2 ]; then
    echo "Usage: $0 <user> <room_id>"
    exit 1
fi

USER=$1
ROOM_ID=$2
HOMESERVER="http://localhost:8008"

# Get access token
ACCESS_TOKEN=$(./api_login.sh "$USER")
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to get access token for $USER" >&2
    exit 1
fi

# Join the room
JOIN_RESULT=$(curl -s -X POST "$HOMESERVER/_matrix/client/r0/rooms/$ROOM_ID/join" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{}")

ROOM_ID_RESULT=$(echo "$JOIN_RESULT" | jq -r '.room_id')

if [ "$ROOM_ID_RESULT" = "null" ] || [ -z "$ROOM_ID_RESULT" ]; then
    echo "ERROR: Failed to join room $ROOM_ID" >&2
    echo "$JOIN_RESULT" >&2
    exit 1
fi

echo "$USER joined room $ROOM_ID"