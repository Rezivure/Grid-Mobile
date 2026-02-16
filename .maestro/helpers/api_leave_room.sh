#!/bin/bash

# Leave a room
# Usage: api_leave_room.sh <user> <room_id>

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

# Leave the room
LEAVE_RESULT=$(curl -s -X POST "$HOMESERVER/_matrix/client/r0/rooms/$ROOM_ID/leave" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{}")

# Matrix returns empty object {} on success
if [ "$?" -eq 0 ]; then
    echo "$USER left room $ROOM_ID"
else
    echo "ERROR: Failed to leave room $ROOM_ID" >&2
    echo "$LEAVE_RESULT" >&2
    exit 1
fi