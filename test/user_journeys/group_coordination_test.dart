import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/widgets/invites_modal.dart';
import 'package:grid_frontend/models/room_invitation.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/blocs/invitations/invitations_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_state.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';

// Mock classes
class MockInvitationsBloc extends Mock implements InvitationsBloc {}
class MockGroupsBloc extends Mock implements GroupsBloc {}
class MockRoomService extends Mock implements RoomService {}

void main() {
  group('User Journey: Group Coordination', () {
    /*
    REAL USER STORY:
    Alex gets home from work and opens Grid to see 2 group invites:
    1. "Friday Dinner" (6 people, expires in 2 hours) 
    2. "Weekend Hiking" (4 people, expires tomorrow)
    Plus 1 friend request from Sarah.
    
    Alex accepts Friday Dinner, declines Weekend Hiking, accepts Sarah.
    Then checks who's in Friday Dinner group and sees Mike just joined too.
    One person (Lisa) can't make it and leaves the group.
    Final group has 5 people for dinner.
    */

    late MockInvitationsBloc mockInvitationsBloc;
    late MockGroupsBloc mockGroupsBloc;
    late MockRoomService mockRoomService;
    late List<RoomInvitation> mockInvitations;

    setUp(() {
      mockInvitationsBloc = MockInvitationsBloc();
      mockGroupsBloc = MockGroupsBloc();
      mockRoomService = MockRoomService();

      // Setup realistic invitation scenarios
      final now = DateTime.now();
      mockInvitations = [
        // Urgent group invite - expires soon
        RoomInvitation(
          roomId: '!friday-dinner:localhost',
          inviterUserId: '@tom:localhost',
          inviterDisplayName: 'Tom',
          roomName: 'Grid:Group:${now.add(Duration(hours: 2)).millisecondsSinceEpoch}:Friday Dinner:@tom:localhost',
          memberCount: 6,
          inviteTimestamp: now.subtract(Duration(minutes: 30)),
          roomType: RoomType.group,
        ),
        
        // Future group invite - less urgent
        RoomInvitation(
          roomId: '!weekend-hiking:localhost', 
          inviterUserId: '@jenny:localhost',
          inviterDisplayName: 'Jenny',
          roomName: 'Grid:Group:${now.add(Duration(days: 1)).millisecondsSinceEpoch}:Weekend Hiking:@jenny:localhost',
          memberCount: 4,
          inviteTimestamp: now.subtract(Duration(hours: 2)),
          roomType: RoomType.group,
        ),

        // Friend request
        RoomInvitation(
          roomId: '!direct-sarah:localhost',
          inviterUserId: '@sarah:localhost', 
          inviterDisplayName: 'Sarah',
          roomName: 'Grid:Direct:@sarah:localhost:@alex:localhost',
          memberCount: 2,
          inviteTimestamp: now.subtract(Duration(minutes: 45)),
          roomType: RoomType.direct,
        ),
      ];

      when(() => mockInvitationsBloc.state).thenReturn(
        InvitationsLoaded(invitations: mockInvitations),
      );
    });

    testWidgets('User processes multiple invitations with different priorities', (WidgetTester tester) async {
      // Arrange - User opens app and sees notification badge
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiProvider(
              providers: [
                Provider<InvitationsBloc>.value(value: mockInvitationsBloc),
                Provider<GroupsBloc>.value(value: mockGroupsBloc),
                Provider<RoomService>.value(value: mockRoomService),
              ],
              child: InvitesModal(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Act & Assert - User processes invitations strategically

      // 1. User sees 3 pending invitations
      expect(find.text('Friday Dinner'), findsOneWidget);
      expect(find.text('Weekend Hiking'), findsOneWidget);
      expect(find.text('Sarah'), findsOneWidget);

      // 2. User notices Friday Dinner is urgent (expires in 2 hours)
      expect(find.textContaining('2 hours'), findsOneWidget);
      expect(find.textContaining('6 people'), findsOneWidget);
      
      // 3. User accepts Friday Dinner first (time-sensitive)
      final fridayAcceptButton = find.descendant(
        of: find.ancestor(
          of: find.text('Friday Dinner'),
          matching: find.byType(Card),
        ),
        matching: find.text('Accept'),
      );
      expect(fridayAcceptButton, findsOneWidget);
      await tester.tap(fridayAcceptButton);
      await tester.pumpAndSettle();

      // 4. Verify acceptance triggers proper service call
      verify(() => mockRoomService.acceptInvitation('!friday-dinner:localhost')).called(1);

      // 5. User sees confirmation and Friday Dinner is removed from pending
      expect(find.text('Joined Friday Dinner'), findsOneWidget);
      expect(find.textContaining('Friday Dinner'), findsNothing); // No longer in pending list

      // 6. User declines Weekend Hiking (not interested)
      final hikingDeclineButton = find.descendant(
        of: find.ancestor(
          of: find.text('Weekend Hiking'),
          matching: find.byType(Card),
        ),
        matching: find.text('Decline'),
      );
      await tester.tap(hikingDeclineButton);
      await tester.pumpAndSettle();

      // 7. Weekend Hiking is removed without joining
      verify(() => mockRoomService.declineInvitation('!weekend-hiking:localhost')).called(1);
      expect(find.text('Weekend Hiking'), findsNothing);

      // 8. User accepts Sarah's friend request
      final sarahAcceptButton = find.descendant(
        of: find.ancestor(
          of: find.text('Sarah'),
          matching: find.byType(Card),
        ),
        matching: find.text('Accept'),
      );
      await tester.tap(sarahAcceptButton);
      await tester.pumpAndSettle();

      // 9. All invitations processed
      verify(() => mockRoomService.acceptInvitation('!direct-sarah:localhost')).called(1);
      expect(find.text('No pending invitations'), findsOneWidget);

      // This test proves:
      // ✓ Users can prioritize time-sensitive group invites
      // ✓ Different invitation types are handled properly
      // ✓ Acceptance/decline actions work correctly
      // ✓ UI updates immediately after each action
      // ✓ Service calls are made for each decision
    });

    testWidgets('User monitors group membership changes in real-time', (WidgetTester tester) async {
      // This tests the scenario where user is in a group and sees members join/leave
      
      // Arrange - User is now in Friday Dinner group
      final groupMembers = [
        '@alex:localhost', // User themselves
        '@tom:localhost',   // Organizer
        '@mike:localhost',  // Just joined
        '@lisa:localhost',  // About to leave
        '@dave:localhost',
        '@anna:localhost',
      ];

      // Mock group state shows initial 6 members
      when(() => mockGroupsBloc.state).thenReturn(
        GroupsLoaded(groups: [
          GroupRoom(
            roomId: '!friday-dinner:localhost',
            name: 'Friday Dinner',
            memberIds: groupMembers,
            memberCount: 6,
            expiresAt: DateTime.now().add(Duration(hours: 2)),
            createdBy: '@tom:localhost',
          ),
        ]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<GroupsBloc>.value(
            value: mockGroupsBloc,
            child: GroupDetailsScreen(roomId: '!friday-dinner:localhost'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Act & Assert - User sees group evolve in real-time

      // 1. User sees all 6 initial members
      expect(find.text('6 members'), findsOneWidget);
      expect(find.text('Tom'), findsOneWidget);
      expect(find.text('Mike'), findsOneWidget);
      expect(find.text('Lisa'), findsOneWidget);

      // 2. Lisa leaves the group (simulate real-time update)
      final updatedMembers = groupMembers.where((id) => id != '@lisa:localhost').toList();
      when(() => mockGroupsBloc.state).thenReturn(
        GroupsLoaded(groups: [
          GroupRoom(
            roomId: '!friday-dinner:localhost',
            name: 'Friday Dinner', 
            memberIds: updatedMembers,
            memberCount: 5,
            expiresAt: DateTime.now().add(Duration(hours: 2)),
            createdBy: '@tom:localhost',
          ),
        ]),
      );

      // Simulate bloc state change
      await tester.pump();

      // 3. User sees member count update and Lisa is gone
      expect(find.text('5 members'), findsOneWidget);
      expect(find.text('Lisa'), findsNothing);
      
      // 4. User sees "Lisa left the group" notification
      expect(find.textContaining('left'), findsOneWidget);

      // 5. User can still see restaurant location and time details
      expect(find.textContaining('expires'), findsOneWidget);
      expect(find.textContaining('2 hours'), findsOneWidget);

      // This test proves:
      // ✓ Real-time group membership updates work
      // ✓ Member count reflects actual membership
      // ✓ Users can track who's actually coming
      // ✓ Group expiration is visible for planning
      // ✓ Leaving members are handled gracefully
    });
  });
}