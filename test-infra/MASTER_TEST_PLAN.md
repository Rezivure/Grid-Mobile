# Grid Mobile — Master Test Plan 🎯

**Goal:** Production-grade test coverage across unit, API integration, and UI E2E layers.
**Current:** 268 tests (223 unit + 45 E2E) | **Target:** 600+ tests

---

## 📊 Coverage Matrix

| Feature | Unit Tests | API Tests | Maestro UI | Status |
|---------|-----------|-----------|------------|--------|
| Auth (login/logout) | ✅ | ✅ | ✅ | DONE |
| Onboarding (8 pages) | — | — | ✅ | DONE |
| Settings navigation | — | — | ✅ | DONE |
| Settings toggles | — | — | ✅ | DONE |
| Models (serialization) | ✅ | — | — | DONE |
| Utilities (formatters) | ✅ | — | — | DONE |
| Direct rooms (contacts) | ✅ room names | ✅ basic | ❌ | PARTIAL |
| Group rooms | ✅ room names | ✅ basic | ❌ | PARTIAL |
| Friend request flow | ❌ | ❌ | ❌ | TODO |
| Group lifecycle | ❌ | ❌ | ❌ | TODO |
| Location sharing | ✅ format | ✅ format | ❌ | PARTIAL |
| Avatars (user + group) | ❌ | ❌ | ❌ | TODO |
| Display name | ❌ | ❌ | ✅ verify | PARTIAL |
| Notifications | ❌ | — | ❌ | TODO |
| Incognito mode | ❌ | — | ✅ toggle | PARTIAL |
| Sign out | ❌ | — | ❌ | TODO |
| Delete account | ❌ | — | ❌ | TODO |
| Sharing windows | ✅ | — | — | DONE |
| Distance calculation | ✅ | — | — | DONE |
| Encryption utils | ✅ | — | — | DONE |
| BLoC state mgmt | ❌ | — | — | TODO |
| Repository layer | ❌ | — | — | TODO |
| Service layer | ❌ | — | — | TODO |
| Map interactions | — | — | ❌ | TODO |

---

## 🔥 PHASE 1: API Test Expansion (grid-api.sh + run-e2e.sh)
**~60 new API tests | Uses existing Synapse infrastructure**

### 1A. Friend Request Lifecycle (10 tests)
```
- user2 sends friend request to user1 (create direct room + invite)
- user1 sees pending invite
- user1 accepts invite → both in room
- user2 sends location → user1 receives it
- user1 sends location → user2 receives it
- Bidirectional location exchange works
- user1 leaves room (unfriend)
- Verify room cleanup after leave
- Re-invite after unfriend works
- Decline friend request → room left, re-invitable
```

### 1B. Group Lifecycle (15 tests)
```
- Create group with 3 members, verify name format
- All members accept invites
- Creator (admin) can invite new member (user4)
- Non-admin CANNOT invite (power level enforced)
- Creator can kick member
- Non-admin CANNOT kick (power level enforced)
- All members share locations → all receive all locations
- Member voluntarily leaves group
- Group with expiration → verify timestamp in name
- Group with 0 expiration → never expires
- Create group with custom name containing special chars
- Group with 2 members (minimum)
- Group with 10 members (stress test)
- Creator leaves → group still exists for others
- Verify group tag (m.tag) is set correctly
```

### 1C. Avatar & Display Name (8 tests)
```
- Set display name via Matrix API
- Get display name → matches what was set
- Change display name → verify update
- Set avatar URL via Matrix API
- Get avatar URL → matches
- Display name with unicode/emoji characters
- Empty display name fallback
- Display name visible to other users in shared room
```

### 1D. Multi-User Scenarios (10 tests)
```
- user1 has 3 direct contacts simultaneously
- user1 is in 3 groups simultaneously
- user1 receives locations from all contacts/groups
- Leave one group, still receiving from others
- Invite same user to direct AND group → both work
- user1 sends location → appears in all rooms they're in
- Rapid location updates (5 in 2 seconds) → all received
- Concurrent room creation (2 users create rooms simultaneously)
- user with no rooms → clean sync response
- 12 users all in one group → locations from all received
```

### 1E. Edge Cases & Error Handling (12 tests)
```
- Invite nonexistent user → proper error
- Create room with invalid name → error
- Send location with missing geo_uri → error/reject
- Send location with invalid coordinates → error
- Double-accept invite (idempotent)
- Double-decline invite (idempotent)
- Leave room you're not in → graceful error
- Join room without invite → rejected
- Create direct room with yourself → error or handled
- Send location to room you've left → error
- Login with wrong password → proper error
- Login with nonexistent user → proper error
```

### 1F. New grid-api.sh Functions Needed
```bash
grid_set_avatar()        # Upload avatar via content API
grid_get_avatar()        # Get avatar URL
grid_set_displayname()   # Already exists
grid_get_displayname()   # Get display name
grid_kick_user()         # Kick from room
grid_get_power_levels()  # Read power levels
grid_get_room_state()    # Read full room state
grid_send_typing()       # Typing indicator
grid_get_room_tags()     # Read room tags
```

---

## 🎬 PHASE 2: Maestro UI Flow Expansion
**~15 new flows | Requires app running against local Synapse**

### 2A. Contact Management Flows
```yaml
11_add_contact.yaml
  - Navigate to contacts/add screen
  - Search for testuser2 (username)
  - Send friend request
  - Verify pending state shown

12_accept_contact.yaml
  - API: testuser2 sends friend request to testuser1
  - App (testuser1): navigate to invitations
  - Tap accept on testuser2's invite
  - Verify contact appears in contacts list

13_decline_contact.yaml
  - API: testuser3 sends friend request to testuser1
  - App: navigate to invitations
  - Tap decline
  - Verify invite removed

14_view_contact_on_map.yaml
  - API: testuser2 sends location to shared room
  - App: verify testuser2's pin appears on map
  - Tap pin → verify info popup
```

### 2B. Group Management Flows
```yaml
15_create_group.yaml
  - Navigate to create group screen
  - Enter group name "TestSquad"
  - Select testuser2 and testuser3
  - Set 1hr expiration
  - Tap create
  - Verify group appears in groups list

16_accept_group_invite.yaml
  - API: testuser2 creates group, invites testuser1
  - App: navigate to invitations
  - Accept group invite
  - Verify group visible

17_group_member_locations.yaml
  - API: all members send locations to group
  - App: open group view
  - Verify multiple pins on map

18_leave_group.yaml
  - Navigate to group settings
  - Tap leave group
  - Confirm dialog
  - Verify group removed from list
```

### 2C. Profile & Avatar Flows
```yaml
19_change_avatar.yaml
  - Navigate to settings
  - Tap avatar/camera icon
  - Select photo (use Maestro's media injection)
  - Verify avatar updated

20_change_display_name.yaml
  - Navigate to settings
  - Tap edit pencil next to display name
  - Enter new name "TestUser"
  - Save
  - Verify name changed on screen
```

### 2D. Account Lifecycle Flows
```yaml
21_sign_out.yaml
  - Navigate to settings
  - Scroll to bottom
  - Tap Sign Out
  - Confirm dialog
  - Verify returned to welcome screen

22_sign_in_after_signout.yaml
  - From welcome screen
  - Custom Provider → login again
  - Verify back on map screen

23_incognito_mode_e2e.yaml
  - Toggle incognito ON
  - API: verify no location events being sent
  - Toggle incognito OFF
  - API: verify location events resume
```

### 2E. Notification Flows
```yaml
24_notification_permission.yaml
  - Fresh install (clearState)
  - Walk through onboarding
  - Accept notification permission when prompted
  - Verify notification settings enabled

25_friend_request_notification.yaml
  - API: testuser2 sends friend request
  - Verify notification banner appears (if foreground)
  - Tap notification → navigates to invitations
```

---

## 🧪 PHASE 3: Unit Test Expansion
**~150 new unit tests | Sub-agent work**

### 3A. BLoC Tests (40 tests)
```
ContactsBloc:
  - LoadContacts → emits ContactsLoaded with list
  - LoadContacts with empty DB → emits empty list
  - AddContact → emits updated list
  - RemoveContact → emits updated list
  - Error state on exception

GroupsBloc:
  - LoadGroups → emits GroupsLoaded
  - CreateGroup → emits new group in list
  - LeaveGroup → group removed from state
  - Expired group filtered out

InvitationsBloc:
  - LoadInvitations → emits list
  - AcceptInvitation → removed from invitations, added to contacts
  - DeclineInvitation → removed from invitations
  - Empty invitations state

MapBloc:
  - LocationUpdate → emits new position
  - MultipleLocations → all pins in state
  - ClearLocations → empty state

AvatarBloc:
  - LoadAvatar → emits avatar URL
  - UpdateAvatar → emits new URL
  - Default avatar when none set
```

### 3B. Repository Tests (30 tests)
```
RoomRepository:
  - Insert and query room
  - Update room members
  - Delete room
  - Query by type (direct/group)
  - Query expired rooms

UserRepository:
  - Insert and get user
  - Update display name
  - Delete user
  - Query direct contacts
  
LocationRepository:
  - Insert location
  - Get latest by user
  - Delete by room
  - Batch insert
```

### 3C. Service Tests with Mocked Matrix Client (40 tests)
```
RoomService:
  - createRoomAndInviteContact → correct room name format
  - createRoomAndInviteContact → user doesn't exist → error
  - createRoomAndInviteContact → already friends → skip
  - createGroup → correct name with expiration
  - createGroup → power levels set correctly
  - createGroup → encryption enabled
  - acceptInvitation → joins room, updates local DB
  - declineInvitation → leaves room, cleans up
  - sendLocationEvent → correct event format
  - sendLocationEvent → filters low accuracy
  - sendLocationEvent → deduplicates close locations
  - leaveRoom → cleans up local data
  - cleanRooms → removes expired groups
  - cleanRooms → keeps non-expired groups

UserService:
  - getRelationshipStatus → already friends
  - getRelationshipStatus → invitation pending
  - getRelationshipStatus → can invite
  - isInSharingWindow → active, in window
  - isInSharingWindow → active, out of window
  - isInSharingWindow → inactive → false
  - isInSharingWindow → no prefs → default true
```

### 3D. Additional Model Tests (20 tests)
```
Room model:
  - copyWith preserves unchanged fields
  - members JSON parsing edge cases
  - isGroup flag conversion
  - Room equality/hashcode

Encryption:
  - Encrypt → decrypt roundtrip
  - Decrypt with wrong key → error
  - Handle large payloads
  - Handle binary data
```

---

## 📋 Execution Order

### Wave 1 (NOW) — API + Maestro in parallel
- **Main agent:** Build Maestro flows 11-18 (contacts + groups), iterate until passing
- **Sub-agent:** Expand API tests (Phases 1A-1E), add new grid-api.sh functions

### Wave 2 — Deep unit tests
- **Sub-agent:** BLoC tests (3A) + Repository tests (3B)
- **Main agent:** Maestro flows 19-25 (avatar, sign out, notifications)

### Wave 3 — Service layer + hardening
- **Sub-agent:** Service tests with mocked Matrix client (3C)
- **Main agent:** Edge case Maestro flows, flaky test fixes, CI optimization

---

## 🎯 Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Total tests | 268 | 600+ |
| Unit tests | 223 | 450+ |
| API integration tests | 35 | 100+ |
| Maestro UI flows | 9 | 25+ |
| CI pipeline | ✅ | ✅ + coverage gate |
| Flaky test rate | unknown | <2% |
| CI run time | ~5m30s | <8m |
