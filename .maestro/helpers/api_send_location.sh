#!/bin/bash

# Send a location message to a room
# Usage: api_send_location.sh <user> <room_id> <lat> <lng> [timestamp]

if [ $# -lt 4 ]; then
    echo "Usage: $0 <user> <room_id> <lat> <lng> [timestamp]"
    exit 1
fi

USER=$1
ROOM_ID=$2
LAT=$3
LNG=$4
TIMESTAMP=${5:-$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")}
HOMESERVER="http://localhost:8008"

# Get access token
ACCESS_TOKEN=$(./api_login.sh "$USER")
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to get access token for $USER" >&2
    exit 1
fi

# Generate transaction ID
TXN_ID=$(date +%s)$RANDOM

# Send location message
LOCATION_DATA=$(curl -s -X PUT "$HOMESERVER/_matrix/client/r0/rooms/$ROOM_ID/send/m.room.message/$TXN_ID" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"msgtype\":\"m.location\",\"geo_uri\":\"geo:$LAT,$LNG\",\"timestamp\":\"$TIMESTAMP\"}")

EVENT_ID=$(echo "$LOCATION_DATA" | jq -r '.event_id')

if [ "$EVENT_ID" = "null" ] || [ -z "$EVENT_ID" ]; then
    echo "ERROR: Failed to send location message" >&2
    echo "$LOCATION_DATA" >&2
    exit 1
fi

echo "Location sent by $USER to room $ROOM_ID: $LAT,$LNG (Event: $EVENT_ID)"