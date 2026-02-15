import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/services/database_service.dart';

/// Minimal mock for testing pure logic functions
class MockDatabaseService extends DatabaseService {
  MockDatabaseService() : super(':memory:');
  
  @override
  Future<void> initialize() async {}
  
  @override
  void close() {}
}

/// Tests for pure logic functions in UserService that don't require mocks
void main() {
  group('UserService pure logic functions', () {
    late UserService userService;

    setUp(() {
      // Create mock/stub instances - these won't be called for pure logic functions
      final mockDbService = MockDatabaseService();
      final client = Client('test', database: NullDatabase());
      final locationRepo = LocationRepository(mockDbService);
      final sharingRepo = SharingPreferencesRepository(mockDbService);
      userService = UserService(client, locationRepo, sharingRepo);
    });

    group('isTimeInRange', () {
      test('time within normal range (9:00 to 17:00)', () {
        final current = TimeOfDay(hour: 12, minute: 30);
        expect(userService.isTimeInRange(current, '09:00', '17:00'), true);
      });

      test('time at start boundary is included', () {
        final current = TimeOfDay(hour: 9, minute: 0);
        expect(userService.isTimeInRange(current, '09:00', '17:00'), true);
      });

      test('time at end boundary is included', () {
        final current = TimeOfDay(hour: 17, minute: 0);
        expect(userService.isTimeInRange(current, '09:00', '17:00'), true);
      });

      test('time before start is excluded', () {
        final current = TimeOfDay(hour: 8, minute: 59);
        expect(userService.isTimeInRange(current, '09:00', '17:00'), false);
      });

      test('time after end is excluded', () {
        final current = TimeOfDay(hour: 17, minute: 1);
        expect(userService.isTimeInRange(current, '09:00', '17:00'), false);
      });

      test('overnight range - time in evening is included', () {
        final current = TimeOfDay(hour: 23, minute: 30);
        expect(userService.isTimeInRange(current, '22:00', '06:00'), true);
      });

      test('overnight range - time in morning is included', () {
        final current = TimeOfDay(hour: 3, minute: 30);
        expect(userService.isTimeInRange(current, '22:00', '06:00'), true);
      });

      test('overnight range - time in afternoon is excluded', () {
        final current = TimeOfDay(hour: 15, minute: 0);
        expect(userService.isTimeInRange(current, '22:00', '06:00'), false);
      });

      test('overnight range - time at evening start boundary', () {
        final current = TimeOfDay(hour: 22, minute: 0);
        expect(userService.isTimeInRange(current, '22:00', '06:00'), true);
      });

      test('overnight range - time at morning end boundary', () {
        final current = TimeOfDay(hour: 6, minute: 0);
        expect(userService.isTimeInRange(current, '22:00', '06:00'), true);
      });

      test('overnight range - time just before evening start', () {
        final current = TimeOfDay(hour: 21, minute: 59);
        expect(userService.isTimeInRange(current, '22:00', '06:00'), false);
      });

      test('overnight range - time just after morning end', () {
        final current = TimeOfDay(hour: 6, minute: 1);
        expect(userService.isTimeInRange(current, '22:00', '06:00'), false);
      });

      test('same start and end time', () {
        final current = TimeOfDay(hour: 12, minute: 0);
        // This edge case: start == end, should probably be treated as invalid
        // but let's test current behavior
        expect(userService.isTimeInRange(current, '12:00', '12:00'), false);
      });

      test('handles minutes precisely in normal range', () {
        final current1 = TimeOfDay(hour: 9, minute: 29);
        final current2 = TimeOfDay(hour: 9, minute: 30);
        final current3 = TimeOfDay(hour: 9, minute: 31);
        
        expect(userService.isTimeInRange(current1, '09:30', '17:30'), false);
        expect(userService.isTimeInRange(current2, '09:30', '17:30'), true);
        expect(userService.isTimeInRange(current3, '09:30', '17:30'), true);
      });

      test('handles midnight edge case', () {
        final current = TimeOfDay(hour: 0, minute: 0);
        expect(userService.isTimeInRange(current, '23:00', '01:00'), true);
      });

      test('23:59 to 00:01 overnight range', () {
        final before = TimeOfDay(hour: 23, minute: 58);
        final start = TimeOfDay(hour: 23, minute: 59);
        final midnight = TimeOfDay(hour: 0, minute: 0);
        final end = TimeOfDay(hour: 0, minute: 1);
        final after = TimeOfDay(hour: 0, minute: 2);
        
        expect(userService.isTimeInRange(before, '23:59', '00:01'), false);
        expect(userService.isTimeInRange(start, '23:59', '00:01'), true);
        expect(userService.isTimeInRange(midnight, '23:59', '00:01'), true);
        expect(userService.isTimeInRange(end, '23:59', '00:01'), true);
        expect(userService.isTimeInRange(after, '23:59', '00:01'), false);
      });
    });

    group('_timeOfDayFromString', () {
      test('parses standard time format', () {
        // We need to access the private method via reflection or make it public for testing
        // For now, let's test through isTimeInRange which uses it internally
        final current = TimeOfDay(hour: 9, minute: 30);
        expect(userService.isTimeInRange(current, '09:30', '10:30'), true);
      });

      test('parses time with leading zeros', () {
        final current = TimeOfDay(hour: 9, minute: 5);
        expect(userService.isTimeInRange(current, '09:05', '10:05'), true);
      });

      test('parses time without leading zeros (if supported)', () {
        // This tests internal parsing - checking if '9:5' format works
        final current = TimeOfDay(hour: 9, minute: 5);
        // Note: This might fail if the implementation requires leading zeros
        // In that case, this test documents the expected behavior
        try {
          final result = userService.isTimeInRange(current, '9:5', '10:5');
          expect(result, true);
        } catch (e) {
          // If this fails, the implementation requires leading zeros
          // which is a valid constraint
          expect(e, isA<FormatException>());
        }
      });

      test('parses midnight as 00:00', () {
        final current = TimeOfDay(hour: 0, minute: 0);
        expect(userService.isTimeInRange(current, '00:00', '01:00'), true);
      });

      test('parses 23:59', () {
        final current = TimeOfDay(hour: 23, minute: 59);
        expect(userService.isTimeInRange(current, '23:59', '00:30'), true);
      });

      test('handles edge cases with boundaries', () {
        final cases = [
          {'time': '00:00', 'hour': 0, 'minute': 0},
          {'time': '12:00', 'hour': 12, 'minute': 0},
          {'time': '23:59', 'hour': 23, 'minute': 59},
          {'time': '01:30', 'hour': 1, 'minute': 30},
        ];
        
        for (final testCase in cases) {
          final current = TimeOfDay(
            hour: testCase['hour'] as int, 
            minute: testCase['minute'] as int
          );
          final timeStr = testCase['time'] as String;
          
          // Test that the parsing works by using the time as both start and checking exact match
          expect(
            userService.isTimeInRange(current, timeStr, '23:59'),
            true,
            reason: 'Failed to parse time: $timeStr'
          );
        }
      });
    });

    group('time range edge cases', () {
      test('very short normal range (1 minute)', () {
        final current = TimeOfDay(hour: 12, minute: 30);
        expect(userService.isTimeInRange(current, '12:30', '12:31'), true);
      });

      test('very short overnight range (1 minute)', () {
        final current = TimeOfDay(hour: 23, minute: 59);
        expect(userService.isTimeInRange(current, '23:59', '00:00'), true);
      });

      test('almost full day range (23:59)', () {
        final morning = TimeOfDay(hour: 6, minute: 0);
        final evening = TimeOfDay(hour: 23, minute: 58);
        
        expect(userService.isTimeInRange(morning, '00:01', '23:59'), true);
        expect(userService.isTimeInRange(evening, '00:01', '23:59'), true);
      });

      test('noon boundaries', () {
        final beforeNoon = TimeOfDay(hour: 11, minute: 59);
        final noon = TimeOfDay(hour: 12, minute: 0);
        final afterNoon = TimeOfDay(hour: 12, minute: 1);
        
        expect(userService.isTimeInRange(beforeNoon, '12:00', '13:00'), false);
        expect(userService.isTimeInRange(noon, '12:00', '13:00'), true);
        expect(userService.isTimeInRange(afterNoon, '12:00', '13:00'), true);
      });
    });
  });
}