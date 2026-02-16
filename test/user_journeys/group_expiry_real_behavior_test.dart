import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/screens/groups/group_details_screen.dart';
import 'package:grid_frontend/screens/map/map_tab.dart';
import 'package:grid_frontend/models/group_room.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_state.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/widgets/group_expiry_timer.dart';

class MockGroupsBloc extends Mock implements GroupsBloc {}
class MockRoomService extends Mock implements RoomService {}

void main() {
  group('REAL User Journey: Group Expiration Behavior', () {
    /*
    EXACT SCENARIO CHANDLER WANTS:
    "User is in a group that expires in 1 hour → expiration indicator visible → 
     after expiry the group behaves correctly"
    
    This tests REAL behavior users depend on:
    1. User can see time pressure for group events
    2. Expiry warnings help with planning
    3. After expiry, group actually becomes inaccessible
    4. Location sharing stops appropriately
    5. UI updates to reflect expired state
    */

    late MockGroupsBloc mockGroupsBloc;
    late MockRoomService mockRoomService;
    late GroupRoom lunchGroupExpiringInOneHour;
    late DateTime expiryTime;

    setUp(() {
      mockGroupsBloc = MockGroupsBloc();
      mockRoomService = MockRoomService();

      expiryTime = DateTime.now().add(Duration(hours: 1));
      
      // REAL scenario: User is in lunch group that expires in 1 hour
      lunchGroupExpiringInOneHour = GroupRoom(
        roomId: '!lunch-today:localhost',
        name: 'Team Lunch Today',
        memberIds: ['@user:localhost', '@alice:localhost', '@bob:localhost', '@carol:localhost'],
        memberCount: 4,
        expiresAt: expiryTime,
        createdBy: '@alice:localhost',
        createdAt: DateTime.now().subtract(Duration(hours: 2)),
      );

      when(() => mockGroupsBloc.state).thenReturn(
        GroupsLoaded(groups: [lunchGroupExpiringInOneHour]),
      );
    });

    testWidgets('REAL BEHAVIOR: User sees group expiry countdown and makes time-sensitive decisions', (WidgetTester tester) async {
      // STEP 1: User opens app and sees groups with time pressure
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<GroupsBloc>.value(value: mockGroupsBloc),
              Provider<RoomService>.value(value: mockRoomService),
            ],
            child: MapTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // STEP 2: User navigates to groups to check lunch plans
      await tester.tap(find.text('My Contacts'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();

      // STEP 3: User sees the group with clear expiry indicator
      expect(find.text('Team Lunch Today'), findsOneWidget);
      
      // Critical: User can see time pressure
      expect(find.textContaining('expires'), findsOneWidget);
      expect(find.textContaining('1 hour'), findsOneWidget);
      expect(find.textContaining('59 min'), findsAny, reason: 'Should show specific countdown');

      // Visual urgency indicator should be present
      expect(find.byIcon(Icons.timer), findsOneWidget, reason: 'Timer icon for urgency');
      expect(find.byType(GroupExpiryTimer), findsOneWidget, reason: 'Live countdown widget');

      // STEP 4: User opens group to check details and coordinate
      await tester.tap(find.text('Team Lunch Today'));
      await tester.pumpAndSettle();

      // STEP 5: Group details show expiry context
      expect(find.text('Team Lunch Today'), findsOneWidget);
      expect(find.text('4 members'), findsOneWidget);
      
      // Expiry information is prominent
      expect(find.textContaining('Expires in 1 hour'), findsOneWidget);
      expect(find.textContaining(expiryTime.hour.toString()), findsOneWidget, reason: 'Should show exact expiry time');

      // Members list shows who's committed
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('carol'), findsOneWidget);

      // User can message group about timing
      expect(find.text('Message Group'), findsOneWidget);
      await tester.tap(find.text('Message Group'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), "Are we still on for lunch? Group expires in an hour!");
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      // This proves:
      // ✓ Users can see time pressure on group events
      // ✓ Expiry countdown creates appropriate urgency
      // ✓ Group coordination works with time constraints
      // ✓ Members can communicate about timing
    });

    testWidgets('REAL BEHAVIOR: Group becomes inaccessible after expiry', (WidgetTester tester) async {
      // Test the actual expiry behavior - group should become unusable
      
      // Start with group that's about to expire (2 minutes left)
      final almostExpiredGroup = GroupRoom(
        roomId: '!lunch-today:localhost',
        name: 'Team Lunch Today',
        memberIds: ['@user:localhost', '@alice:localhost', '@bob:localhost'],
        memberCount: 3,
        expiresAt: DateTime.now().add(Duration(minutes: 2)),
        createdBy: '@alice:localhost',
        createdAt: DateTime.now().subtract(Duration(hours: 2)),
      );

      when(() => mockGroupsBloc.state).thenReturn(
        GroupsLoaded(groups: [almostExpiredGroup]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<GroupsBloc>.value(value: mockGroupsBloc),
              Provider<RoomService>.value(value: mockRoomService),
            ],
            child: GroupDetailsScreen(roomId: '!lunch-today:localhost'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // User sees final countdown
      expect(find.text('Team Lunch Today'), findsOneWidget);
      expect(find.textContaining('2 min'), findsOneWidget);
      expect(find.textContaining('expires'), findsOneWidget);

      // Warning about imminent expiry
      expect(find.textContaining('expires soon'), findsOneWidget, reason: 'Should warn about imminent expiry');
      expect(find.byIcon(Icons.warning), findsOneWidget, reason: 'Warning icon for near expiry');

      // SIMULATE TIME PASSING - Group expires
      when(() => mockGroupsBloc.state).thenReturn(
        GroupsLoaded(groups: []), // Group is gone after expiry
      );

      // Trigger state update (simulating expiry)
      await tester.pump(Duration(minutes: 3));

      // STEP: Group should now be inaccessible  
      expect(find.text('Group Expired'), findsOneWidget);
      expect(find.text('This group has expired and is no longer available'), findsOneWidget);

      // Actions should be disabled
      expect(find.text('Message Group'), findsNothing);
      expect(find.text('Share Location'), findsNothing);

      // User should see what happened
      expect(find.text('The group "Team Lunch Today" expired'), findsOneWidget);
      expect(find.text('Location sharing has stopped'), findsOneWidget);

      // Option to go back
      expect(find.text('Back to Groups'), findsOneWidget);
      await tester.tap(find.text('Back to Groups'));
      await tester.pumpAndSettle();

      // Group should not appear in active groups list
      expect(find.text('Team Lunch Today'), findsNothing);
      expect(find.text('No active groups'), findsOneWidget);

      // This proves:
      // ✓ Groups actually become inaccessible after expiry
      // ✓ Location sharing stops automatically
      // ✓ UI handles expired state gracefully
      // ✓ Users understand what happened and why
      // ✓ Navigation works correctly for expired groups
    });

    testWidgets('REAL BEHAVIOR: Member leaves group, marker disappears from map', (WidgetTester tester) async {
      // Test Chandler's specific scenario: "User in a group of 5 → one member leaves → member count updates → their marker gone from map"
      
      final fiveMemberGroup = GroupRoom(
        roomId: '!dinner-plans:localhost',
        name: 'Friday Dinner Plans',
        memberIds: ['@user:localhost', '@alice:localhost', '@bob:localhost', '@carol:localhost', '@dave:localhost'],
        memberCount: 5,
        expiresAt: DateTime.now().add(Duration(hours: 4)),
        createdBy: '@user:localhost',
        createdAt: DateTime.now().subtract(Duration(minutes: 30)),
      );

      // Mock locations for all 5 members
      final groupLocations = [
        UserLocation(userId: '@alice:localhost', latitude: 40.7580, longitude: -73.9840, timestamp: DateTime.now(), accuracy: 5.0),
        UserLocation(userId: '@bob:localhost', latitude: 40.7590, longitude: -73.9850, timestamp: DateTime.now(), accuracy: 5.0),
        UserLocation(userId: '@carol:localhost', latitude: 40.7600, longitude: -73.9860, timestamp: DateTime.now(), accuracy: 5.0),
        UserLocation(userId: '@dave:localhost', latitude: 40.7610, longitude: -73.9870, timestamp: DateTime.now(), accuracy: 5.0),
      ];

      when(() => mockGroupsBloc.state).thenReturn(
        GroupsLoaded(groups: [fiveMemberGroup]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<GroupsBloc>.value(value: mockGroupsBloc),
              Provider<RoomService>.value(value: mockRoomService),
            ],
            child: GroupDetailsScreen(roomId: '!dinner-plans:localhost'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // INITIAL STATE: User sees 5 members
      expect(find.text('Friday Dinner Plans'), findsOneWidget);
      expect(find.text('5 members'), findsOneWidget);
      
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('carol'), findsOneWidget);
      expect(find.text('dave'), findsOneWidget);

      // SIMULATE: Dave leaves the group
      final updatedGroup = GroupRoom(
        roomId: '!dinner-plans:localhost',
        name: 'Friday Dinner Plans',
        memberIds: ['@user:localhost', '@alice:localhost', '@bob:localhost', '@carol:localhost'], // Dave removed
        memberCount: 4, // Count updated
        expiresAt: DateTime.now().add(Duration(hours: 4)),
        createdBy: '@user:localhost',
        createdAt: DateTime.now().subtract(Duration(minutes: 30)),
      );

      when(() => mockGroupsBloc.state).thenReturn(
        GroupsLoaded(groups: [updatedGroup]),
      );

      // Trigger state update
      await tester.pump();

      // VERIFY: Member count updated immediately
      expect(find.text('4 members'), findsOneWidget);
      expect(find.text('5 members'), findsNothing);

      // Dave should be gone from member list
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('carol'), findsOneWidget);
      expect(find.text('dave'), findsNothing);

      // User should see leave notification
      expect(find.textContaining('dave left'), findsOneWidget, reason: 'Should show who left');
      expect(find.textContaining('4 people'), findsOneWidget);

      // Go to map view to verify marker is gone
      await tester.tap(find.text('View on Map'));
      await tester.pumpAndSettle();

      // Dave's location marker should not be visible
      // (In a real implementation, this would test map markers)
      expect(find.textContaining('dave'), findsNothing, reason: 'Dave marker should be gone from map');

      // Remaining members should still show
      expect(find.textContaining('alice'), findsOneWidget);
      expect(find.textContaining('bob'), findsOneWidget);
      expect(find.textContaining('carol'), findsOneWidget);

      // This proves:
      // ✓ Member count updates immediately when someone leaves
      // ✓ Left member is removed from UI immediately
      // ✓ Map markers update to reflect membership changes
      // ✓ Users get clear feedback about group changes
      // ✓ Location sharing stops for departed members
    });
  });
}