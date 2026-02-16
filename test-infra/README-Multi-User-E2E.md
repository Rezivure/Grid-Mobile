# Grid-Mobile Multi-User E2E Tests

This directory contains comprehensive end-to-end tests that combine Matrix API orchestration with Maestro UI verification to test multi-user scenarios.

## Overview

These tests validate the core Grid-Mobile functionality by:
1. **API Setup**: Using Matrix client-server API to simulate other users' actions
2. **UI Verification**: Using Maestro to verify the Grid-Mobile app UI reflects those changes correctly

## Test Coverage

### High-Priority Flows

1. **Location Sharing E2E** (`e2e_01_incoming_location_sharing.yaml`)
   - API: testuser2 sends location update → UI: testuser1 sees location on map
   
2. **Friend Request Received** (`e2e_02_friend_request_received.yaml`)  
   - API: testuser2 sends friend request → UI: testuser1 sees notification/invite
   
3. **Group Invitation** (`e2e_03_group_invite_received.yaml`)
   - API: testuser2 creates group and invites testuser1 → UI: testuser1 sees invite
   
4. **Multiple Simultaneous Locations** (`e2e_04_multiple_locations_map.yaml`)
   - API: 3+ users send locations → UI: testuser1 sees all markers on map
   
5. **Group Member Locations** (`e2e_05_group_member_locations.yaml`)
   - API: testuser2 sends location in shared group → UI: testuser1 sees it on map
   
6. **Display Name Propagation** (`e2e_06_display_name_propagation.yaml`)
   - API: testuser2 changes display name → UI: testuser1 sees updated name everywhere
   
7. **User Presence/Status** (`e2e_07_user_presence_status.yaml`)
   - API: testuser2 changes presence → UI: testuser1 sees status indicators update
   
8. **Group Removal** (`e2e_08_removed_from_group.yaml`)
   - API: testuser2 kicks testuser1 → UI: group disappears from testuser1's view
   
9. **Friend Request Acceptance API** (`e2e_09_friend_request_accepted_api.yaml`)
   - UI: testuser1 accepts request → API: testuser2 sees acceptance and can interact

## Prerequisites

### 1. Synapse Test Server
- Docker with Synapse server running on `localhost:8008`
- Test accounts `testuser1-12` with password `testpass123`

### 2. Test Infrastructure
- Maestro CLI installed and configured
- Grid-Mobile app built and ready for testing
- Test helper scripts in `test-infra/scripts/`

### 3. Device Setup
- iOS Simulator or Android Emulator running
- Grid-Mobile app installed on the test device
- testuser1 logged in and on the map screen (starting state)

## Running Tests

### Quick Start

```bash
# Run all multi-user E2E tests
./test-infra/scripts/run-multi-user-e2e-comprehensive.sh
```

### Individual Tests

```bash
# Run a specific test
maestro test .maestro/e2e_01_incoming_location_sharing.yaml
```

### Advanced Options

```bash
# Run with stress testing (8+ simultaneous users)
./test-infra/scripts/run-multi-user-e2e-comprehensive.sh --stress

# Run with performance monitoring
./test-infra/scripts/run-multi-user-e2e-comprehensive.sh --performance

# Clean up test state only
./test-infra/scripts/run-multi-user-e2e-comprehensive.sh --cleanup-only
```

## Architecture

### API Orchestration Layer

**`grid-api.sh`** - Low-level Matrix API functions:
- `grid_login <user> [password]` - Login as test user
- `grid_create_direct <target_user>` - Create direct room (friend request)
- `grid_create_group <name> <duration> <user1> [user2]...` - Create group and invite users
- `grid_send_location <room_id> <lat> <lon>` - Send location update
- `grid_accept_invite <room_id>` / `grid_decline_invite <room_id>` - Handle invitations
- `grid_set_presence <status> [message]` - Set presence/status
- `grid_kick_user <room_id> <user_id> [reason]` - Remove user from room

**`api-helpers.sh`** - High-level test setup functions:
- `setup_incoming_location [lat] [lon]` - testuser2 sends location to testuser1
- `setup_friend_request_notification` - testuser2 sends friend request
- `setup_group_invite [name] [duration]` - testuser2 creates group and invites testuser1
- `setup_multiple_friend_requests [count]` - Multiple users send requests
- `cleanup_test_state` - Reset all test accounts and rooms

### UI Verification Layer

**Maestro YAML Files** - Each test combines:
1. **API Setup**: `runScript` blocks that call helper functions
2. **UI Actions**: Standard Maestro commands (`tapOn`, `assertVisible`, etc.)
3. **Verification**: Assertions that UI state matches API changes
4. **Cleanup**: State reset between test phases

### Test Flow Pattern

```yaml
# 1. API Setup
- runScript: |
    source api-helpers.sh
    setup_incoming_location 40.7580 -73.9855
    wait_for_sync 5

# 2. UI Verification  
- launchApp
- assertVisible: "My Contacts"
- extendedWaitUntil:
    visible: "testuser2"
    timeout: 10000

# 3. Interaction Testing
- tapOn: "testuser2"
- assertVisible: "Times Square"
```

## Test Environment

### Synapse Configuration
- Homeserver: `http://localhost:8008`
- Federation disabled (local testing only)
- Registration open for test accounts
- E2EE enabled but with test keys

### Test Accounts
- **testuser1**: Main UI test account (logged into app)
- **testuser2-12**: API orchestration accounts (simulated remote users)
- All accounts use password: `testpass123`

### Geographic Test Data
Tests use real NYC coordinates for realistic location testing:
- Times Square: `40.7580, -73.9855`
- Central Park: `40.7829, -73.9654`  
- Brooklyn Bridge: `40.7061, -73.9969`
- Wall Street: `40.7074, -74.0113`

## Debugging

### Common Issues

**"No notification badge visible"**
- Check Synapse server is running: `curl http://localhost:8008/_matrix/client/versions`
- Verify API setup completed: check script output for "✓" confirmations
- Increase wait times: `wait_for_sync 10` instead of `wait_for_sync 5`

**"User not found on map"** 
- Verify location was sent: check API script logs
- Ensure contact request was accepted in UI
- Check app is in foreground and on map screen

**"Test timeouts"**
- Matrix sync can be slow in test environment
- Increase Maestro timeouts: `timeout: 15000`
- Check device performance and memory

### Debug Mode

```bash
# Enable debug output
GRID_DEBUG=1 maestro test .maestro/e2e_01_incoming_location_sharing.yaml

# Check API responses
source test-infra/scripts/grid-api.sh
grid_login testuser2
grid_whoami
```

### Log Files
- Maestro output: `/tmp/maestro_output.log`
- API responses: Check script echo statements
- Test state: `/tmp/test_*_room_id` files

## Performance Considerations

These tests are comprehensive but can be resource-intensive:

- **Duration**: Each test takes 2-5 minutes
- **Full suite**: ~30-45 minutes for all 9 tests
- **Network**: Makes numerous Matrix API calls
- **Device**: Tests complex UI interactions with real data

For faster feedback during development, run individual tests:

```bash
# Quick location sharing test (most common failure point)
maestro test .maestro/e2e_01_incoming_location_sharing.yaml

# Quick friend request test  
maestro test .maestro/e2e_02_friend_request_received.yaml
```

## Contributing

When adding new multi-user E2E tests:

1. **API Setup**: Add helper functions to `api-helpers.sh`
2. **Maestro Flow**: Create new `.maestro/e2e_XX_test_name.yaml` file
3. **Test Runner**: Add to test suite in `run-multi-user-e2e-comprehensive.sh`
4. **Documentation**: Update this README with new test description

### Test Naming Convention
- `e2e_XX_descriptive_name.yaml` - Multi-user E2E tests
- `XX` - Priority order (01-09 are core flows)
- Use underscores, not hyphens
- Include brief description in filename

### Best Practices
- Always clean up test state between phases
- Use realistic geographic coordinates
- Include both positive and negative test cases
- Verify API state changes in addition to UI
- Add appropriate timeouts for async operations
- Document any new Matrix API calls in `grid-api.sh`