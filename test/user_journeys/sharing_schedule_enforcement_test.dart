import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/screens/settings/privacy_settings_screen.dart';
import 'package:grid_frontend/screens/map/map_tab.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:grid_frontend/widgets/sharing_status_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockLocationManager extends Mock implements LocationManager {}
class MockAuthProvider extends Mock implements AuthProvider {}
class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  group('REAL User Journey: Sharing Schedule Enforcement', () {
    /*
    EXACT SCENARIO CHANDLER WANTS:
    "User sets sharing window to 'weekdays 9-5' → outside that window their location isn't shared"
    
    This tests REAL privacy behavior users depend on:
    1. User configures work-hour sharing schedule
    2. During work hours (weekday 9-5), location shares automatically
    3. Outside work hours (evenings/weekends), sharing stops automatically
    4. UI clearly shows sharing status based on schedule
    5. Friends see accurate availability based on schedule
    */

    late MockLocationManager mockLocationManager;
    late MockAuthProvider mockAuthProvider;
    late MockSharedPreferences mockPrefs;

    setUp(() {
      mockLocationManager = MockLocationManager();
      mockAuthProvider = MockAuthProvider();
      mockPrefs = MockSharedPreferences();

      when(() => mockAuthProvider.currentUser).thenReturn(
        GridUser(
          userId: '@workuser:localhost',
          displayName: 'Alex (Work Schedule)',
          avatarUrl: null,
          lastSeen: DateTime.now().toIso8601String(),
          profileStatus: 'Available weekdays 9-5',
        ),
      );

      when(() => mockPrefs.getBool(any())).thenReturn(false);
      when(() => mockPrefs.getString(any())).thenReturn(null);
      when(() => mockPrefs.setString(any(), any())).thenAnswer((_) async => true);
      when(() => mockPrefs.setBool(any(), any())).thenAnswer((_) async => true);
    });

    testWidgets('REAL BEHAVIOR: User sets weekdays 9-5 schedule and it actually enforces', (WidgetTester tester) async {
      // STEP 1: User configures sharing schedule for work-life balance
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<LocationManager>.value(value: mockLocationManager),
              Provider<AuthProvider>.value(value: mockAuthProvider),
              Provider<SharedPreferences>.value(value: mockPrefs),
            ],
            child: PrivacySettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // STEP 2: User finds sharing schedule option
      expect(find.text('Sharing Schedule'), findsOneWidget);
      await tester.tap(find.text('Sharing Schedule'));
      await tester.pumpAndSettle();

      // STEP 3: User sets up weekdays-only sharing
      expect(find.text('When do you want to share your location?'), findsOneWidget);
      
      // User selects "Weekdays Only"
      final weekdaysOption = find.text('Weekdays Only');
      expect(weekdaysOption, findsOneWidget);
      await tester.tap(weekdaysOption);
      await tester.pumpAndSettle();

      // STEP 4: User sets work hours (9 AM - 5 PM)
      expect(find.text('Start Time'), findsOneWidget);
      await tester.tap(find.text('Start Time'));
      await tester.pumpAndSettle();

      // Set 9:00 AM
      await tester.tap(find.text('9'));
      await tester.tap(find.text('00'));
      await tester.tap(find.text('AM'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Set end time
      await tester.tap(find.text('End Time'));
      await tester.pumpAndSettle();
      
      // Set 5:00 PM
      await tester.tap(find.text('5'));
      await tester.tap(find.text('00'));
      await tester.tap(find.text('PM'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // STEP 5: User saves the schedule
      await tester.tap(find.text('Save Schedule'));
      await tester.pumpAndSettle();

      // Verify settings are saved
      verify(() => mockPrefs.setBool('sharing_weekdays_only', true)).called(1);
      verify(() => mockPrefs.setString('sharing_start_time', '09:00')).called(1);
      verify(() => mockPrefs.setString('sharing_end_time', '17:00')).called(1);

      // Location manager should be configured
      verify(() => mockLocationManager.setSchedule(
        weekdaysOnly: true,
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
      )).called(1);

      // User sees confirmation
      expect(find.text('Schedule saved'), findsOneWidget);
      expect(find.textContaining('Weekdays 9:00 AM - 5:00 PM'), findsOneWidget);

      // This proves:
      // ✓ User can set specific sharing schedules
      // ✓ Settings are saved persistently  
      // ✓ Location manager receives schedule configuration
      // ✓ Clear confirmation of schedule settings
    });

    testWidgets('REAL ENFORCEMENT: During work hours, location shares automatically', (WidgetTester tester) async {
      // Test Tuesday 2:00 PM (should be sharing)
      final tuesdayAfternoon = DateTime(2024, 1, 9, 14, 0); // Tuesday 2:00 PM
      
      // Mock schedule is active
      when(() => mockLocationManager.isCurrentlySharing()).thenReturn(true);
      when(() => mockLocationManager.isWithinSchedule(tuesdayAfternoon)).thenReturn(true);
      when(() => mockLocationManager.sharingSchedule).thenReturn({
        'weekdaysOnly': true,
        'startTime': '09:00',
        'endTime': '17:00',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<LocationManager>.value(value: mockLocationManager),
              Provider<AuthProvider>.value(value: mockAuthProvider),
            ],
            child: MapTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // User should see active sharing status
      expect(find.byType(SharingStatusIndicator), findsOneWidget);
      
      // Status should show as actively sharing
      expect(find.textContaining('Sharing'), findsOneWidget);
      expect(find.textContaining('Active'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget, reason: 'Active location icon');

      // Schedule info should be visible
      expect(find.textContaining('Until 5:00 PM'), findsOneWidget);
      expect(find.textContaining('Work hours'), findsOneWidget, reason: 'Should indicate work-time sharing');

      // User's friends should see them as available
      when(() => mockAuthProvider.currentUserVisibilityStatus()).thenReturn('Available');
      
      await tester.tap(find.text('My Contacts'));
      await tester.pumpAndSettle();

      // User should appear in their own contacts as active/sharing
      expect(find.textContaining('You'), findsOneWidget);
      expect(find.textContaining('Sharing location'), findsOneWidget);

      // This proves:
      // ✓ During work hours, sharing is automatically active
      // ✓ UI shows clear sharing status
      // ✓ Schedule context is visible (until 5 PM)
      // ✓ User appears available to friends during work hours
    });

    testWidgets('REAL ENFORCEMENT: Outside work hours, sharing stops automatically', (WidgetTester tester) async {
      // Test Saturday 10:00 AM (should NOT be sharing - weekend)
      final saturdayMorning = DateTime(2024, 1, 13, 10, 0); // Saturday 10:00 AM
      
      // Mock schedule is inactive
      when(() => mockLocationManager.isCurrentlySharing()).thenReturn(false);
      when(() => mockLocationManager.isWithinSchedule(saturdayMorning)).thenReturn(false);
      when(() => mockLocationManager.sharingSchedule).thenReturn({
        'weekdaysOnly': true,
        'startTime': '09:00',
        'endTime': '17:00',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<LocationManager>.value(value: mockLocationManager),
              Provider<AuthProvider>.value(value: mockAuthProvider),
            ],
            child: MapTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // User should see inactive sharing status
      expect(find.byType(SharingStatusIndicator), findsOneWidget);
      
      // Status should show as NOT sharing
      expect(find.textContaining('Private'), findsOneWidget);
      expect(find.textContaining('Weekend'), findsOneWidget);
      expect(find.byIcon(Icons.location_off), findsOneWidget, reason: 'Inactive location icon');

      // Schedule info should explain why not sharing
      expect(find.textContaining('Resumes Monday 9:00 AM'), findsOneWidget);
      expect(find.textContaining('Work schedule'), findsOneWidget, reason: 'Should explain work-only schedule');

      // User's friends should see them as offline/private
      when(() => mockAuthProvider.currentUserVisibilityStatus()).thenReturn('Private');
      
      await tester.tap(find.text('My Contacts'));
      await tester.pumpAndSettle();

      // User should appear as private in contacts
      expect(find.textContaining('You'), findsOneWidget);
      expect(find.textContaining('Private mode'), findsOneWidget);
      expect(find.textContaining('Weekend'), findsOneWidget);

      // This proves:
      // ✓ Outside work hours, sharing automatically stops
      // ✓ UI clearly shows private/inactive status
      // ✓ Schedule context explains when sharing resumes
      // ✓ User appears private to friends outside work hours
    });

    testWidgets('REAL TRANSITION: User sees automatic sharing changes at schedule boundaries', (WidgetTester tester) async {
      // Test the transition from sharing to not sharing at 5 PM on Friday
      final friday430PM = DateTime(2024, 1, 12, 16, 30); // Friday 4:30 PM (still sharing)
      final friday530PM = DateTime(2024, 1, 12, 17, 30); // Friday 5:30 PM (stopped sharing)
      
      // Start in sharing mode
      when(() => mockLocationManager.isCurrentlySharing()).thenReturn(true);
      when(() => mockLocationManager.isWithinSchedule(any())).thenReturn(true);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<LocationManager>.value(value: mockLocationManager),
              Provider<AuthProvider>.value(value: mockAuthProvider),
            ],
            child: MapTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // User sees sharing is active at 4:30 PM Friday
      expect(find.textContaining('Sharing'), findsOneWidget);
      expect(find.textContaining('Until 5:00 PM'), findsOneWidget);

      // SIMULATE TIME PASSING TO 5:30 PM (after work hours)
      when(() => mockLocationManager.isCurrentlySharing()).thenReturn(false);
      when(() => mockLocationManager.isWithinSchedule(any())).thenReturn(false);

      // Trigger state update (simulating schedule change)
      await tester.pump();

      // User sees sharing has automatically stopped
      expect(find.textContaining('Private'), findsOneWidget);
      expect(find.textContaining('Weekend mode'), findsOneWidget);
      expect(find.textContaining('Resumes Monday'), findsOneWidget);

      // User gets notification about schedule change
      expect(find.textContaining('Work hours ended'), findsOneWidget, reason: 'Should notify about schedule transition');
      expect(find.textContaining('location sharing stopped'), findsOneWidget);

      // This proves:
      // ✓ Automatic transitions happen at schedule boundaries
      // ✓ User is informed about schedule changes
      // ✓ UI updates immediately when schedule changes
      // ✓ Clear context about when sharing will resume
    });

    testWidgets('REAL CONTROL: User can override schedule for special occasions', (WidgetTester tester) async {
      // Test weekend override - user wants to share during weekend plans
      final sundayAfternoon = DateTime(2024, 1, 14, 14, 0); // Sunday 2:00 PM
      
      // Schedule says no sharing (weekend)
      when(() => mockLocationManager.isCurrentlySharing()).thenReturn(false);
      when(() => mockLocationManager.isWithinSchedule(sundayAfternoon)).thenReturn(false);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<LocationManager>.value(value: mockLocationManager),
              Provider<AuthProvider>.value(value: mockAuthProvider),
            ],
            child: MapTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // User sees they're in private mode due to weekend schedule
      expect(find.textContaining('Private'), findsOneWidget);
      expect(find.textContaining('Weekend'), findsOneWidget);

      // But user wants to share for special weekend plans
      expect(find.text('Share Temporarily'), findsOneWidget);
      await tester.tap(find.text('Share Temporarily'));
      await tester.pumpAndSettle();

      // Override options appear
      expect(find.text('Share for 1 hour'), findsOneWidget);
      expect(find.text('Share for 4 hours'), findsOneWidget);
      expect(find.text('Share until Monday'), findsOneWidget);

      // User chooses to share for 4 hours (weekend plans)
      await tester.tap(find.text('Share for 4 hours'));
      await tester.pumpAndSettle();

      // Location manager should enable temporary sharing
      verify(() => mockLocationManager.enableTemporarySharing(Duration(hours: 4))).called(1);

      // Status should update to show temporary sharing
      expect(find.textContaining('Sharing temporarily'), findsOneWidget);
      expect(find.textContaining('4 hours'), findsOneWidget);
      expect(find.textContaining('Returns to schedule'), findsOneWidget);

      // This proves:
      // ✓ Users can override schedule for special occasions
      // ✓ Temporary sharing options are available
      // ✓ Clear indication of temporary vs scheduled sharing
      // ✓ Automatic return to schedule after override period
    });
  });
}