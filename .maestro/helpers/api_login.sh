#!/bin/bash

# Get access token for a user
# Usage: api_login.sh <username>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1
PASSWORD="testpass123"
HOMESERVER="http://localhost:8008"

# Login and get access token
ACCESS_TOKEN=$(curl -s -X POST "$HOMESERVER/_matrix/client/r0/login" \
    -d "{\"type\":\"m.login.password\",\"user\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
    -H "Content-Type: application/json" | jq -r '.access_token')

if [ "$ACCESS_TOKEN" = "null" ] || [ -z "$ACCESS_TOKEN" ]; then
    echo "ERROR: Failed to get access token for $USERNAME" >&2
    exit 1
fi

echo "$ACCESS_TOKEN"