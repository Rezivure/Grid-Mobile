#!/bin/bash
# Setup a single friend with location
# Usage: ./setup_friend_with_location.sh <friend_user> [lat] [lon]

set -e
cd "$(dirname "$0")"

FRIEND_USER=${1:-testuser2}  
LAT=${2:-40.7580}
LON=${3:-73.9855}

echo "Setting up friend $FRIEND_USER with location $LAT,$LON..."

# Login the friend user
./api_login.sh $FRIEND_USER testpass123

# Send friend request to testuser1
./api_send_friend_request.sh $FRIEND_USER testuser1

# Send location
./api_send_location.sh $FRIEND_USER $LAT $LON

echo "Friend $FRIEND_USER setup complete"