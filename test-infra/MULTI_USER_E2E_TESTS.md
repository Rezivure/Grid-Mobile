# Multi-User End-to-End Tests

This directory contains comprehensive multi-user E2E tests that combine API-driven setup with UI verification. These tests represent the most valuable test scenarios as they verify real product experiences with actual multi-user interactions.

## Overview

The multi-user E2E tests use a two-phase approach:
1. **API Setup Phase**: Use Matrix APIs to create realistic multi-user scenarios (friend requests, location sharing, groups, etc.)
2. **UI Verification Phase**: Use Maestro to verify that the app UI correctly reflects the API changes

This approach tests the complete data flow: API → Matrix server → app sync → UI updates.

## Test Infrastructure

### Key Files

- **`scripts/grid-api.sh`**: Core Matrix API helper functions that emulate Grid app behavior
- **`scripts/api-helpers.sh`**: High-level setup functions for multi-user scenarios  
- **`scripts/run-multi-user-e2e.sh`**: Test runner for all multi-user E2E tests
- **`.maestro/46-61_*.yaml`**: Individual Maestro test flows

### Test Environment

- **Synapse Server**: Local Matrix homeserver at `localhost:8008`
- **Test Accounts**: `testuser1-12` with password `testpass123`
- **Primary Test User**: `testuser1` (the UI user - logged into the app)
- **API Test Users**: `testuser2-5` (controlled via API to create scenarios)

## Test Scenarios

### 1. Incoming Location Update (`46_incoming_location_update.yaml`)
- **API Setup**: `testuser2` creates direct room with `testuser1` and sends location
- **UI Verification**: Location marker/avatar appears on `testuser1`'s map
- **Tests**: Real-time location sync, map marker display, contact relationship establishment

### 2. Notification Badge Friend Request (`47_notification_badge_friend_request.yaml`)  
- **API Setup**: `testuser2` sends friend request to `testuser1`
- **UI Verification**: Notification bell shows badge, invite appears in notifications modal
- **Tests**: Notification system, invite UI, friend request acceptance flow

### 3. Accept Group Invite Flow (`48_accept_group_invite_flow.yaml`)
- **API Setup**: `testuser2` creates group "Pizza Night Party" and invites `testuser1`
- **UI Verification**: Group invite appears, user can accept, group shows in contacts
- **Tests**: Group invitation system, group membership, contacts integration

### 4. Decline Group Invite Flow (`49_decline_group_invite_flow.yaml`)
- **API Setup**: `testuser2` creates group "Declined Test Group" and invites `testuser1`
- **UI Verification**: User can decline invite, group doesn't appear in contacts
- **Tests**: Invite decline functionality, negative case verification

### 5. Contact Goes Incognito (`56_contact_goes_incognito.yaml`)
- **API Setup**: `testuser2` shares location then goes incognito (leaves room)
- **UI Verification**: Marker disappears or shows stale/offline indicator
- **Tests**: Privacy mode, location sharing states, offline contact display

### 6. Group Member Leaves (`57_group_member_leaves.yaml`)
- **API Setup**: Create group with both users, `testuser1` joins, `testuser2` leaves
- **UI Verification**: Member count updates, `testuser2` removed from member list
- **Tests**: Dynamic group membership, member count accuracy, group state sync

### 7. Avatar Update Propagation (`58_avatar_update_propagation.yaml`)
- **API Setup**: `testuser2` sets new avatar via Matrix API
- **UI Verification**: Updated avatar shows in contacts, map markers, and profile views
- **Tests**: Avatar synchronization, profile updates, UI consistency across views

### 8. Multiple Friend Requests (`59_multiple_friend_requests.yaml`)
- **API Setup**: `testuser2-5` all send friend requests to `testuser1`
- **UI Verification**: All requests appear in notifications, proper badge count
- **Tests**: Bulk notification handling, notification count accuracy, mass acceptance

### 9. Location History Trail (`60_location_history_trail.yaml`)
- **API Setup**: `testuser2` sends sequence of locations simulating movement
- **UI Verification**: Movement trail or history visible on map
- **Tests**: Location history, movement tracking, temporal location data

### 10. Sign Out Clean State (`61_sign_out_clean_state.yaml`)
- **API Setup**: Create test data (friends, groups) then sign out and back in
- **UI Verification**: Clean state on re-login, no stale data persistence  
- **Tests**: State management, data cleanup, fresh login experience

## Usage

### Run All Multi-User E2E Tests
```bash
cd test-infra/scripts
./run-multi-user-e2e.sh
```

### Run Specific Test
```bash
./run-multi-user-e2e.sh --test "46_incoming_location_update.yaml"
# or by name
./run-multi-user-e2e.sh --test "Incoming Location Update"
```

### Prerequisites
1. **Docker running**: `cd test-infra && docker compose up -d`
2. **Synapse accessible**: Verify `http://localhost:8008` responds
3. **Maestro installed**: `maestro --version` works
4. **testuser1 logged in**: Tests assume primary user is authenticated

## API Helper Functions

The `api-helpers.sh` script provides high-level setup functions:

```bash
source api-helpers.sh

# Setup functions
setup_incoming_location [lat] [lon]           # testuser2 sends location
setup_friend_request_notification             # testuser2 sends friend request  
setup_group_invite [name] [duration]          # testuser2 creates group
setup_group_member_leaves [name]              # Create group, member leaves
setup_avatar_update [avatar_url]              # testuser2 updates avatar
setup_multiple_friend_requests [count]        # Multiple users send requests
setup_location_trail [room_id]                # testuser2 sends location sequence
setup_contact_incognito                       # testuser2 goes private
cleanup_test_state                            # Clean up all test data
wait_for_sync [seconds]                       # Wait for sync propagation
```

## Technical Details

### Matrix API Emulation
The `grid-api.sh` script precisely emulates Grid app behavior:

- **Room Creation**: Uses exact naming conventions (`Grid:Direct:...`, `Grid:Group:...`)
- **Invitations**: Matches Grid's invitation flow and power level settings
- **Location Events**: Sends `m.location` events with proper `geo_uri` format
- **Encryption**: Enables `m.megolm.v1.aes-sha2` encryption like the app

### Sync Timing
Multi-user tests require careful timing:
- **API calls complete immediately** but sync propagation takes time
- **`wait_for_sync`** functions provide appropriate delays
- **UI verification** includes `extendedWaitUntil` for async updates

### Error Handling
- **Timeout protection**: All tests have 300s timeout
- **Graceful degradation**: Optional assertions for flaky UI elements
- **State cleanup**: Each test cleans up after itself
- **Detailed logging**: Failed tests show last 20 lines of output

## Best Practices

### Writing New Multi-User E2E Tests
1. **Start with API setup**: Use `runScript:` to call helper functions
2. **Wait for sync**: Always call `wait_for_sync` after API operations
3. **Test positive paths first**: Verify expected behavior works
4. **Add negative cases**: Verify things that shouldn't happen don't happen
5. **Clean up**: Tests should not affect each other

### Debugging Test Failures
1. **Check Synapse logs**: `docker compose logs synapse`
2. **Verify API calls**: Run helper functions manually in terminal
3. **Check app state**: Use Maestro screenshots or debug UI
4. **Increase wait times**: Sync can be slow under load

### Adding New Scenarios
1. **Add helper function** to `api-helpers.sh` for API setup
2. **Create Maestro YAML** for UI verification
3. **Add to test list** in `run-multi-user-e2e.sh`
4. **Test locally** before committing

## Integration with CI/CD

These tests are designed for:
- **Local development**: Full multi-user scenario testing
- **PR validation**: Verify multi-user features don't break
- **Release verification**: Ensure complete user flows work

### Performance Considerations
- **Full suite**: ~20-30 minutes (includes Docker setup, multiple logins)
- **Individual tests**: 2-5 minutes each
- **Parallel execution**: Not recommended (shared test accounts)

## Troubleshooting

### Common Issues

**"Synapse not accessible"**
```bash
cd test-infra && docker compose up -d
curl http://localhost:8008/_matrix/client/versions
```

**"Login failed"**
```bash
cd test-infra/scripts && ./setup-accounts.sh
```

**"Test timeout"**
- Increase wait times in test
- Check if app is responding to touches
- Verify device/simulator performance

**"Stale test data"**
```bash
source api-helpers.sh && cleanup_test_state
```

### Test Data Persistence
- Tests use `testuser1-5` for multi-user scenarios
- `testuser6-12` reserved for other test types
- State persists in Synapse database between runs
- Use `cleanup_test_state` to reset

## Future Enhancements

Potential additions to the multi-user E2E test suite:

1. **Location sharing permissions**: Test accept/deny location requests
2. **Group expiration**: Verify time-based group auto-deletion
3. **Cross-device sync**: Multi-device scenarios  
4. **Network interruption**: Test offline/online sync behavior
5. **Large group management**: 10+ member groups
6. **Location accuracy**: GPS simulation with realistic coordinates
7. **Push notification integration**: Test with real push notifications

These multi-user E2E tests represent the gold standard for testing real product workflows and should be the primary validation mechanism for Grid's multi-user features.