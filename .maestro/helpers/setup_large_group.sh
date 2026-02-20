#!/bin/bash
# Setup a large group with many members
# Usage: ./setup_large_group.sh <group_name> <start_user> <end_user> [duration_seconds]

set -e
cd "$(dirname "$0")"

GROUP_NAME=${1:-LargeTestGroup}
START_USER=${2:-1}
END_USER=${3:-11}
DURATION=${4:-7200}

echo "Setting up large group '$GROUP_NAME' with users $START_USER to $END_USER..."

# Login all users
echo "Logging in users..."
for i in $(seq $START_USER $END_USER); do
    ./api_login.sh testuser$i testpass123 &
done
wait

# Create the group (using user 2 as creator)
echo "Creating group..."
./api_create_group.sh testuser$START_USER "$GROUP_NAME" $DURATION

# Add all other users to the group
echo "Adding users to group..."
for i in $(seq $((START_USER + 1)) $END_USER); do
    ./api_join_room.sh testuser$i "$GROUP_NAME" &
done
wait

# All members send clustered locations (close together)
echo "Setting up member locations..."
BASE_LAT=40.7580
BASE_LON=-73.9855
USER_COUNT=$((END_USER - START_USER + 1))

for i in $(seq $START_USER $END_USER); do
    # Spread users in a small area (0.001 degree increments)
    OFFSET=$(((i - START_USER) * 1))
    LAT=$(python3 -c "print(f'{$BASE_LAT + $OFFSET * 0.0001:.6f}')")
    LON=$(python3 -c "print(f'{$BASE_LON + $OFFSET * 0.0001:.6f}')")
    ./api_send_location.sh testuser$i $LAT $LON &
done
wait

echo "Large group '$GROUP_NAME' setup complete with $USER_COUNT members"