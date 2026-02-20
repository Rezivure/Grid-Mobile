#!/bin/bash
# Setup many friends with locations for load testing
# Usage: ./setup_many_friends.sh <start_user_num> <end_user_num>

set -e
cd "$(dirname "$0")"

START_USER=${1:-2}
END_USER=${2:-10}

echo "Setting up users $START_USER to $END_USER..."

# Login multiple users in parallel
echo "Logging in users..."
for i in $(seq $START_USER $END_USER); do
    ./api_login.sh testuser$i testpass123 &
done
wait

# Send friend requests from all users to testuser1
echo "Sending friend requests..."
for i in $(seq $START_USER $END_USER); do
    ./api_send_friend_request.sh testuser$i testuser1 &
done
wait

# Set up NYC area locations for all users
echo "Setting up locations..."
LOCATIONS=(
    "40.7580,-73.9855"  # Times Square
    "40.7614,-73.9776"  # Central Park
    "40.7505,-73.9934"  # High Line
    "40.7589,-73.9851"  # Bryant Park
    "40.7648,-73.9808"  # Lincoln Center
    "40.7543,-73.9860"  # Chelsea Market  
    "40.7536,-73.9832"  # Union Square
    "40.7558,-73.9865"  # Madison Square Garden
    "40.7624,-73.9738"  # Columbus Circle
)

USER_INDEX=0
for i in $(seq $START_USER $END_USER); do
    LOC_INDEX=$((USER_INDEX % ${#LOCATIONS[@]}))
    LAT_LON=${LOCATIONS[$LOC_INDEX]}
    LAT=$(echo $LAT_LON | cut -d',' -f1)
    LON=$(echo $LAT_LON | cut -d',' -f2)
    ./api_send_location.sh testuser$i $LAT $LON &
    USER_INDEX=$((USER_INDEX + 1))
done
wait

echo "Setup complete for users $START_USER to $END_USER"