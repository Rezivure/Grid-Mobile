#!/bin/sh
# Creates test accounts on local Synapse via open registration

SYNAPSE_URL="http://synapse:8008"

echo "Waiting for Synapse..."
sleep 3

register_user() {
  local username="$1"
  local password="$2"

  RESULT=$(curl -s -X POST "${SYNAPSE_URL}/_matrix/client/v3/register" \
    -H "Content-Type: application/json" \
    -d "{
      \"username\": \"${username}\",
      \"password\": \"${password}\",
      \"auth\": {\"type\": \"m.login.dummy\"},
      \"inhibit_login\": true
    }")

  # Check for user_id in response (success) or error
  echo "$RESULT" | grep -q "user_id" && echo "  ✓ ${username}" || echo "  ✗ ${username}: $(echo $RESULT | head -c 80)"
}

echo "========================================"
echo " Grid Test Account Setup"
echo "========================================"
echo ""

echo "Creating test users..."
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  register_user "testuser${i}" "testpass123"
done

echo ""
echo "========================================"
echo " Setup complete!"
echo "========================================"
echo ""
echo "Users:  testuser1-12 / testpass123"
echo "Server: ${SYNAPSE_URL}"
