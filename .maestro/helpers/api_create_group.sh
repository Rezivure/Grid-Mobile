#!/bin/bash

# Create a group room and invite members
# Usage: api_create_group.sh <creator> <name> <member1> [member2] [member3] ...

if [ $# -lt 3 ]; then
    echo "Usage: $0 <creator> <name> <member1> [member2] [member3] ..."
    exit 1
fi

CREATOR=$1
GROUP_NAME=$2
shift 2
MEMBERS=("$@")
HOMESERVER="http://localhost:8008"

# Get access token for creator
ACCESS_TOKEN=$(./api_login.sh "$CREATOR")
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to get access token for $CREATOR" >&2
    exit 1
fi

# Create group room
ROOM_DATA=$(curl -s -X POST "$HOMESERVER/_matrix/client/r0/createRoom" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$GROUP_NAME\",\"preset\":\"private_chat\",\"is_direct\":false}")

ROOM_ID=$(echo "$ROOM_DATA" | jq -r '.room_id')

if [ "$ROOM_ID" = "null" ] || [ -z "$ROOM_ID" ]; then
    echo "ERROR: Failed to create group room" >&2
    echo "$ROOM_DATA" >&2
    exit 1
fi

# Invite each member
for MEMBER in "${MEMBERS[@]}"; do
    INVITE_RESULT=$(curl -s -X POST "$HOMESERVER/_matrix/client/r0/rooms/$ROOM_ID/invite" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"user_id\":\"@$MEMBER:localhost\"}")
    
    echo "Invited $MEMBER to group $GROUP_NAME"
done

echo "Group '$GROUP_NAME' created by $CREATOR (Room: $ROOM_ID)"