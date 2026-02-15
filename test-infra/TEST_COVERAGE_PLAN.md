# Grid Mobile — Test Coverage Plan

**Created:** 2026-02-14
**Goal:** Go from 0% to solid foundational test coverage enabling CI automation.

---

## Architecture Overview

```
lib/
├── models/          # Pure Dart data classes (Room, GridUser, UserLocation, SharingWindow, SharingPreferences, etc.)
├── repositories/    # DB access layer (SQLite via DatabaseService, SharedPreferences)
├── services/        # Business logic (RoomService, UserService, SyncManager, LocationManager)
├── blocs/           # State management (Contacts, Groups, Invitations, Map, Avatar, MapIcons)
├── providers/       # Riverpod/Provider state holders
├── screens/         # Flutter UI screens
├── widgets/         # Reusable Flutter widgets
├── utilities/       # Pure Dart helpers (utils.dart, time_ago_formatter.dart, encryption_utils.dart)
└── styles/          # Theme definitions
```

## Testability Assessment

| Layer | Testability | Notes |
|-------|-------------|-------|
| Models | ★★★★★ | Pure Dart, no dependencies. Ideal for unit tests. |
| Utilities | ★★★★☆ | Mostly pure Dart. `formatUserId` depends on `dotenv`. |
| Services (logic) | ★★★☆☆ | Core logic extractable, but tightly coupled to Matrix `Client`. Needs mocking. |
| Repositories | ★★★☆☆ | SQLite-backed. Need in-memory DB or mocked `DatabaseService`. |
| BLoCs | ★★★☆☆ | Standard bloc pattern. Testable with `bloc_test` + mocked repos/services. |
| Widgets/Screens | ★★☆☆☆ | Heavy platform dependencies (maps, geolocation, Matrix SDK). |

---

## Priority 1 — Unit Tests (Pure Dart, No Flutter)

**Target: ~60 tests | Effort: 1-2 days | Impact: HIGH**

### 1.1 Model Serialization

| Model | Tests |
|-------|-------|
| `Room` | `fromMap` / `toMap` roundtrip, `fromJson` / `toJson`, corrupted `members` field (plain string, empty, invalid JSON), `isGroup` int↔bool conversion, `copyWith` |
| `GridUser` | `fromMap` / `toMap` roundtrip, nullable fields (`displayName`, `avatarUrl`, `profileStatus`), `fromJson` / `toJson` |
| `SharingWindow` | `fromJson` / `toJson`, missing `isActive` defaults to `true`, empty `days` list |
| `SharingPreferences` | `fromMap` / `toMap`, `activeSharing` int↔bool, `sharePeriods` JSON encoding/decoding, null `shareWindows` |
| `UserLocation` | Requires encryption key — test constructor and `position` getter only (encryption tested separately) |

### 1.2 Room Name Parsing & Conventions

| Function/Method | Tests |
|-----------------|-------|
| `isDirectRoom()` | Valid direct name, non-direct name, partial match, empty string |
| `extractExpirationTimestamp()` | Valid group name, expired timestamp, `0` (never expires), malformed name, direct room name |
| `RoomService.isRoomExpired()` | Expired group, non-expired group, `0` expiration (never), non-group room, malformed name |
| Room name format | Verify `Grid:Direct:<user1>:<user2>` and `Grid:Group:<expiration>:<name>:<creator>` parsing |

### 1.3 Utility Functions

| Function | Tests |
|----------|-------|
| `localpart()` | Standard Matrix ID, already clean ID |
| `getFirstLetter()` | Normal username, `@`-prefixed, empty string |
| `timeAgo()` | Seconds, minutes, hours, days ago |
| `generateColorFromUsername()` | Deterministic (same input → same output), different inputs → different colors |
| `formatUserId()` | Default homeserver (strips domain), custom homeserver (keeps full ID), malformed ID |
| `isCustomHomeserver()` | Default server, custom server, with/without `https://`, port stripping, empty string |
| `parseGroupName()` | Valid group name, no prefix, no suffix |

### 1.4 Sharing Window Logic

| Method | Tests |
|--------|-------|
| `isTimeInRange()` | Normal range (09:00-17:00): inside, outside, boundary |
| | Overnight range (22:00-06:00): inside (23:00), inside (03:00), outside (12:00) |
| | Edge: start == end, midnight crossing |
| `_timeOfDayFromString()` | "09:00", "23:59", "00:00" |

### 1.5 Distance Calculation

| Method | Tests |
|--------|-------|
| `_calculateDistance()` | Same point → 0, known city pair (verify within 1% of actual), antipodal points |

---

## Priority 2 — Repository Tests (Mocked DB)

**Target: ~30 tests | Effort: 2-3 days | Impact: MEDIUM**

Requires: `sqflite_common_ffi` for in-memory SQLite testing.

| Repository | Key Tests |
|------------|-----------|
| `RoomRepository` | Insert/query/delete room, update members, query expired rooms, query by type (direct/group) |
| `LocationRepository` | Insert location, get latest, delete by user, handle no results |
| `UserRepository` | Insert/get/delete user, direct contacts query, orphan cleanup, user relationships |
| `InvitationsRepository` | Save/load/clear from SharedPreferences (use `shared_preferences` test helper) |
| `SharingPreferencesRepository` | CRUD for preferences, query by targetId+targetType, handle missing records |

---

## Priority 3 — BLoC Tests

**Target: ~20 tests | Effort: 2 days | Impact: MEDIUM**

Requires: `bloc_test`, `mocktail` or `mockito`.

| BLoC | Key Tests |
|------|-----------|
| `ContactsBloc` | Initial state, `LoadContacts` → `ContactsLoaded`, error → `ContactsError` |
| `GroupsBloc` | Load groups, create group event, member add/remove |
| `InvitationsBloc` | Load invitations, accept → state update, decline → state update |
| `MapBloc` | Location update events, zoom level calculations |

---

## Priority 4 — Service Tests (Mocked Matrix Client)

**Target: ~25 tests | Effort: 3-4 days | Impact: HIGH but hard**

Requires: Mocked `Client`, `Room`, `User` from `package:matrix`.

| Service | Key Tests |
|---------|-----------|
| `RoomService.createRoomAndInviteContact()` | Verify room name format `Grid:Direct:<me>:<them>`, user existence check, relationship status check |
| `RoomService.createGroup()` | Verify name format `Grid:Group:<exp>:<name>:<creator>`, power levels, encryption state |
| `RoomService.sendLocationEvent()` | Event content format (`geo_uri`, `timestamp`), accuracy filtering (>100m skipped), distance dedup (<10m skipped) |
| `RoomService.updateRooms()` | Filters non-Grid rooms, skips expired groups, checks sharing windows, batches sends |
| `RoomService.isRoomExpired()` | (Already in Priority 1 — pure logic) |
| `UserService.getRelationshipStatus()` | Already friends, invitation sent, can invite |
| `UserService.isInSharingWindow()` | Active sharing → true, no prefs → true, window match, window miss |
| `UserService.isGroupInSharingWindow()` | Same as above for group type |

---

## Priority 5 — Widget Tests

**Target: ~10 tests | Effort: 2 days | Impact: LOW**

| Widget/Screen | Key Tests |
|---------------|-----------|
| Settings page | Username display: default homeserver shows localpart, custom shows full ID |
| Welcome screen | Login/signup buttons visible |
| Onboarding | Page navigation between steps |

---

## Dependencies to Add

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.0          # Mocking without codegen (preferred over mockito for simplicity)
  bloc_test: ^9.0.0         # BLoC testing utilities
  fake_async: ^1.3.0        # Control time in tests
  shared_preferences: ^2.0.0 # Already a dep — use setMockInitialValues in tests
  # For repository tests (later):
  # sqflite_common_ffi: ^2.0.0
```

---

## Test File Structure

```
test/
├── models/
│   ├── room_test.dart
│   ├── grid_user_test.dart
│   ├── sharing_window_test.dart
│   ├── sharing_preferences_test.dart
│   └── user_location_test.dart
├── services/
│   ├── room_name_test.dart
│   ├── sharing_window_logic_test.dart
│   ├── distance_test.dart
│   └── room_service_test.dart       (Priority 4)
├── utilities/
│   ├── utils_test.dart
│   └── time_ago_test.dart
├── blocs/                            (Priority 3)
│   ├── contacts_bloc_test.dart
│   ├── groups_bloc_test.dart
│   └── invitations_bloc_test.dart
└── widgets/                          (Priority 5)
    └── settings_page_test.dart
```

---

## CI Integration

1. **Run:** `flutter test --coverage --machine > test-results.json`
2. **Coverage:** `genhtml coverage/lcov.info -o coverage/html`
3. **Gate:** Fail PR if coverage drops below threshold (start at 20%, increase over time)
4. **Script:** `test-infra/scripts/run-unit-tests.sh`

---

## Rollout Plan

| Week | Focus | Expected Coverage |
|------|-------|-------------------|
| 1 | Priority 1 (models, utils, pure logic) | ~15% |
| 2 | Priority 2 (repositories with mocked DB) | ~25% |
| 3 | Priority 3 (BLoC tests) | ~35% |
| 4 | Priority 4 (service tests with mocked Matrix) | ~50% |
| 5+ | Priority 5 (widgets) + increase coverage on existing | ~60%+ |
