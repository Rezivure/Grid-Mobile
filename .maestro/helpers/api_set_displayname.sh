#!/bin/bash

# Set display name for a user
# Usage: api_set_displayname.sh <user> <display_name>

if [ $# -ne 2 ]; then
    echo "Usage: $0 <user> <display_name>"
    exit 1
fi

USER=$1
DISPLAY_NAME=$2
HOMESERVER="http://localhost:8008"

# Get access token
ACCESS_TOKEN=$(./api_login.sh "$USER")
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to get access token for $USER" >&2
    exit 1
fi

# Set display name
NAME_RESULT=$(curl -s -X PUT "$HOMESERVER/_matrix/client/r0/profile/@$USER:localhost/displayname" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"displayname\":\"$DISPLAY_NAME\"}")

# Matrix returns empty object {} on success
if [ "$?" -eq 0 ]; then
    echo "Display name set for $USER: $DISPLAY_NAME"
else
    echo "ERROR: Failed to set display name for $USER" >&2
    echo "$NAME_RESULT" >&2
    exit 1
fi