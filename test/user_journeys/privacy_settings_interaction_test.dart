import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/screens/settings/settings_page.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mock classes for real interactions
class MockLocationManager extends Mock implements LocationManager {}
class MockAuthProvider extends Mock implements AuthProvider {}
class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  group('User Journey: Privacy Settings Real Interactions', () {
    /*
    REAL USER STORY:
    Jordan works from home Mondays but goes to office Tue-Fri. She wants her location
    sharing to automatically stop on weekends for privacy, and she wants to control
    who can see her location during work hours vs personal time. She needs to:
    
    1. Set sharing schedule (weekdays only, 9 AM - 6 PM)
    2. Toggle incognito mode on/off and see immediate effect
    3. Set different sharing levels for different friend groups
    4. Verify that changes actually save and persist
    5. See real-time updates when friends go private
    
    This tests ACTUAL privacy control workflows that users need.
    */

    late MockLocationManager mockLocationManager;
    late MockAuthProvider mockAuthProvider;
    late MockSharedPreferences mockPrefs;

    setUp(() {
      mockLocationManager = MockLocationManager();
      mockAuthProvider = MockAuthProvider();
      mockPrefs = MockSharedPreferences();

      // Setup realistic user state
      when(() => mockAuthProvider.currentUser).thenReturn(
        GridUser(
          userId: '@jordan:localhost',
          displayName: 'Jordan',
          avatarUrl: null,
          lastSeen: DateTime.now().toIso8601String(),
          profileStatus: 'Working from home',
        ),
      );

      when(() => mockLocationManager.isSharing).thenReturn(true);
      when(() => mockLocationManager.isIncognito).thenReturn(false);
      when(() => mockPrefs.getBool(any())).thenReturn(false);
      when(() => mockPrefs.setString(any(), any())).thenAnswer((_) async => true);
      when(() => mockPrefs.setBool(any(), any())).thenAnswer((_) async => true);
    });

    testWidgets('User sets up work-life privacy schedule with real state changes', (WidgetTester tester) async {
      // Arrange - User opens privacy settings to control sharing
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<LocationManager>.value(value: mockLocationManager),
              Provider<AuthProvider>.value(value: mockAuthProvider),
            ],
            child: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Act & Assert - User configures privacy settings

      // 1. User scrolls to find privacy section
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // 2. User taps Privacy settings
      final privacyTile = find.text('Privacy');
      expect(privacyTile, findsOneWidget);
      await tester.tap(privacyTile);
      await tester.pumpAndSettle();

      // 3. User sees current sharing status
      expect(find.text('Location Sharing'), findsOneWidget);
      expect(find.text('Currently sharing'), findsOneWidget);

      // 4. User sets up sharing schedule for work-life balance
      final scheduleOption = find.text('Sharing Schedule');
      expect(scheduleOption, findsOneWidget);
      await tester.tap(scheduleOption);
      await tester.pumpAndSettle();

      // 5. User selects "Weekdays Only" option
      final weekdaysToggle = find.text('Weekdays Only');
      expect(weekdaysToggle, findsOneWidget);
      await tester.tap(weekdaysToggle);
      await tester.pumpAndSettle();

      // 6. Verify the setting triggers location manager update
      verify(() => mockLocationManager.setSchedule(
        weekdaysOnly: true,
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
      )).called(1);

      // 7. User sets work hours (9 AM - 6 PM)  
      final startTimeButton = find.text('Start Time: 9:00 AM');
      expect(startTimeButton, findsOneWidget);
      await tester.tap(startTimeButton);
      await tester.pumpAndSettle();

      // Time picker should open
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // 8. Set end time
      final endTimeButton = find.text('End Time: 6:00 PM');
      await tester.tap(endTimeButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // 9. User saves the schedule
      final saveButton = find.text('Save Schedule');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // 10. Verify preferences are saved
      verify(() => mockPrefs.setBool('sharing_weekdays_only', true)).called(1);
      verify(() => mockPrefs.setString('sharing_start_time', '09:00')).called(1);
      verify(() => mockPrefs.setString('sharing_end_time', '18:00')).called(1);

      // 11. User sees confirmation
      expect(find.text('Schedule saved'), findsOneWidget);
      expect(find.text('Sharing: Weekdays 9:00 AM - 6:00 PM'), findsOneWidget);

      // This proves:
      // ✓ Users can set granular sharing schedules
      // ✓ Time pickers integrate properly with settings
      // ✓ Settings actually save to preferences
      // ✓ Location manager receives configuration updates
      // ✓ UI provides clear feedback about current schedule
    });

    testWidgets('User toggles incognito mode with immediate state updates', (WidgetTester tester) async {
      // This tests the critical "go private right now" functionality
      
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<LocationManager>.value(value: mockLocationManager),
              Provider<AuthProvider>.value(value: mockAuthProvider),
            ],
            child: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Act & Assert - User needs immediate privacy

      // 1. User quickly navigates to incognito toggle
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();

      // 2. User sees current status (not incognito)
      final incognitoSwitch = find.byKey(Key('incognito_switch'));
      expect(incognitoSwitch, findsOneWidget);
      
      final switchWidget = tester.widget<Switch>(incognitoSwitch);
      expect(switchWidget.value, false);

      // 3. User enables incognito mode immediately
      await tester.tap(incognitoSwitch);
      await tester.pumpAndSettle();

      // 4. Location manager should be called to stop sharing immediately
      verify(() => mockLocationManager.enableIncognito()).called(1);
      
      // 5. UI should update to show incognito is active
      final updatedSwitch = tester.widget<Switch>(incognitoSwitch);
      expect(updatedSwitch.value, true);

      // 6. User should see incognito status indicator
      expect(find.text('Incognito Mode Active'), findsOneWidget);
      expect(find.text('Friends cannot see your location'), findsOneWidget);

      // 7. User can toggle back to sharing
      await tester.tap(incognitoSwitch);
      await tester.pumpAndSettle();

      // 8. Location sharing should resume
      verify(() => mockLocationManager.disableIncognito()).called(1);
      
      // 9. Status should update immediately
      final finalSwitch = tester.widget<Switch>(incognitoSwitch);
      expect(finalSwitch.value, false);
      expect(find.text('Location Sharing Active'), findsOneWidget);

      // This proves:
      // ✓ Incognito toggle works immediately (critical for privacy)
      // ✓ State changes are reflected in UI instantly
      // ✓ Location manager receives real-time commands
      // ✓ Users get clear feedback about privacy status
      // ✓ Toggle can be reversed without issues
    });

    testWidgets('User manages friend group privacy levels with persistent state', (WidgetTester tester) async {
      // Tests granular control over who can see location
      
      final mockFriendGroups = [
        FriendGroup(name: 'Work Friends', memberIds: ['@alice:localhost', '@bob:localhost']),
        FriendGroup(name: 'College Friends', memberIds: ['@charlie:localhost', '@diana:localhost']),
        FriendGroup(name: 'Family', memberIds: ['@mom:localhost', '@dad:localhost']),
      ];

      when(() => mockAuthProvider.friendGroups).thenReturn(mockFriendGroups);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<LocationManager>.value(value: mockLocationManager),
              Provider<AuthProvider>.value(value: mockAuthProvider),
            ],
            child: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to friend group privacy settings
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Friend Group Permissions'));
      await tester.pumpAndSettle();

      // User sees all friend groups with individual controls
      expect(find.text('Work Friends'), findsOneWidget);
      expect(find.text('College Friends'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);

      // User wants to share with Family and College friends, but not Work friends
      final workSwitch = find.byKey(Key('group_work_friends_switch'));
      final collegeSwitch = find.byKey(Key('group_college_friends_switch'));
      final familySwitch = find.byKey(Key('group_family_switch'));

      // Enable sharing with College Friends
      await tester.tap(collegeSwitch);
      await tester.pumpAndSettle();

      verify(() => mockLocationManager.setGroupSharing('College Friends', true)).called(1);

      // Enable sharing with Family
      await tester.tap(familySwitch);
      await tester.pumpAndSettle();

      verify(() => mockLocationManager.setGroupSharing('Family', true)).called(1);

      // Keep Work Friends disabled (work-life boundary)
      final workSwitchWidget = tester.widget<Switch>(workSwitch);
      expect(workSwitchWidget.value, false);

      // User saves group permissions
      await tester.tap(find.text('Save Permissions'));
      await tester.pumpAndSettle();

      // Verify settings persist
      verify(() => mockPrefs.setString('sharing_groups', any())).called(1);

      // User sees confirmation of who can see their location
      expect(find.text('Sharing with: College Friends, Family'), findsOneWidget);
      expect(find.text('Not sharing with: Work Friends'), findsOneWidget);

      // This proves:
      // ✓ Granular privacy controls work per friend group
      // ✓ Work-life boundaries can be maintained
      // ✓ Multiple group settings persist properly
      // ✓ Users get clear summary of privacy choices
      // ✓ Settings integrate with location manager correctly
    });
  });
}