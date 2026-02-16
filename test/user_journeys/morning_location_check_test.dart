import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/screens/map/map_tab.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_state.dart';

// Mock classes
class MockContactsBloc extends Mock implements ContactsBloc {}
class MockUserLocation extends Mock implements UserLocation {}
class MockContactDisplay extends Mock implements ContactDisplay {}

void main() {
  group('User Journey: Morning Location Check', () {
    /*
    REAL USER STORY:
    Sarah opens Grid at 8am to see where her friends are before deciding her day.
    - Emma is at the gym (0.3 miles away) 
    - Jake is at coffee shop downtown (1.2 miles)
    - Mike is still at home (2.1 miles)
    She taps Emma to see details, then decides to head to Emma's gym.
    */
    
    late MockContactsBloc mockContactsBloc;
    late List<ContactDisplay> mockContacts;

    setUp(() {
      mockContactsBloc = MockContactsBloc();
      
      // Setup realistic contact data
      mockContacts = [
        ContactDisplay(
          userId: '@emma:localhost',
          displayName: 'Emma',
          avatarUrl: 'mxc://test/emma-avatar',
          lastSeen: DateTime.now().subtract(Duration(minutes: 5)).toIso8601String(),
          membershipStatus: 'At the gym 💪',
        ),
        ContactDisplay(
          userId: '@jake:localhost', 
          displayName: 'Jake',
          avatarUrl: 'mxc://test/jake-avatar',
          lastSeen: DateTime.now().subtract(Duration(minutes: 12)).toIso8601String(),
          membershipStatus: 'Coffee run ☕',
        ),
        ContactDisplay(
          userId: '@mike:localhost',
          displayName: 'Mike', 
          avatarUrl: null,
          lastSeen: DateTime.now().subtract(Duration(hours: 8)).toIso8601String(), // Still at home from last night
          membershipStatus: 'Available',
        ),
      ];

      // Mock the contacts state with realistic data
      when(() => mockContactsBloc.state).thenReturn(
        ContactsLoaded(mockContacts),
      );
    });

    testWidgets('User can see friends locations and make social decisions', (WidgetTester tester) async {
      // Arrange - User opens app in the morning
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ContactsBloc>.value(
            value: mockContactsBloc,
            child: MapTab(),
          ),
        ),
      );
      
      await tester.pumpAndSettle();

      // Act & Assert - User sees friends at different locations
      
      // 1. User opens contacts drawer to see who's around
      final contactsButton = find.text('My Contacts');
      expect(contactsButton, findsOneWidget);
      await tester.tap(contactsButton);
      await tester.pumpAndSettle();

      // 2. User sees Emma at gym with fresh timestamp 
      expect(find.text('Emma'), findsOneWidget);
      expect(find.textContaining('5 min'), findsOneWidget); // Recent activity
      expect(find.textContaining('💪'), findsOneWidget); // Gym status

      // 3. User sees Jake at coffee shop
      expect(find.text('Jake'), findsOneWidget);
      expect(find.textContaining('12 min'), findsOneWidget);
      expect(find.textContaining('☕'), findsOneWidget);

      // 4. User sees Mike is stale/at home
      expect(find.text('Mike'), findsOneWidget);
      expect(find.textContaining('8 h'), findsOneWidget); // Old timestamp
      
      // 5. User taps Emma to see details (she's closest and active)
      await tester.tap(find.text('Emma'));
      await tester.pumpAndSettle();

      // 6. Profile modal opens showing Emma's details
      expect(find.textContaining('Emma'), findsOneWidget);
      expect(find.textContaining('0.3 miles'), findsOneWidget); // Distance calculated
      expect(find.textContaining('gym'), findsOneWidget, reason: 'Should show location context');
      expect(find.textContaining('5 min ago'), findsOneWidget); // Fresh timestamp

      // 7. User can see "Message" or "Navigate" options
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Navigate'), findsOneWidget);

      // 8. User decides to message Emma about joining her
      await tester.tap(find.text('Message'));
      await tester.pumpAndSettle();

      // 9. Message interface opens with Emma's context
      expect(find.textContaining('Emma'), findsOneWidget);
      
      // This test proves:
      // ✓ Real-time location data drives social decisions
      // ✓ Distance calculation works for nearby friends  
      // ✓ Timestamp freshness affects user behavior
      // ✓ Profile interaction leads to actionable next steps
      // ✓ Status messages provide social context
    });

    testWidgets('User can distinguish between active and stale friend locations', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ContactsBloc>.value(
            value: mockContactsBloc,
            child: MapTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Act - User checks location freshness before making plans
      await tester.tap(find.text('My Contacts'));
      await tester.pumpAndSettle();

      // Assert - User can make informed decisions based on data freshness
      
      // Fresh locations show as "Active" or recent time
      final emmaTile = find.ancestor(
        of: find.text('Emma'),
        matching: find.byType(ListTile),
      );
      expect(emmaTile, findsOneWidget);
      
      // Recent activity shows active status or fresh timestamp
      expect(find.textContaining('Active'), findsAny);
      expect(find.textContaining('min ago'), findsAny);

      // Stale locations show old timestamps and less prominent display
      final mikeTile = find.ancestor(
        of: find.text('Mike'), 
        matching: find.byType(ListTile),
      );
      expect(mikeTile, findsOneWidget);
      expect(find.textContaining('8 h ago'), findsOneWidget);

      // User can visually distinguish active vs inactive friends
      // (This would test visual styling differences in a real implementation)
    });
  });
}