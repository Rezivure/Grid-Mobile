import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure logic functions extracted from UserService for testing
class UserServiceTestHelper {
  /// Helper to check if a time falls within a given range
  /// Copied from UserService.isTimeInRange for testing
  static bool isTimeInRange(TimeOfDay current, String startTime, String endTime) {
    final start = _timeOfDayFromString(startTime);
    final end = _timeOfDayFromString(endTime);

    if (start.hour < end.hour ||
        (start.hour == end.hour && start.minute < end.minute)) {
      // Normal range (e.g., 09:00 to 17:00)
      return (current.hour > start.hour ||
          (current.hour == start.hour && current.minute >= start.minute)) &&
          (current.hour < end.hour ||
              (current.hour == end.hour && current.minute <= end.minute));
    } else {
      // Overnight range (e.g., 22:00 to 06:00)
      return (current.hour > start.hour ||
          (current.hour == start.hour && current.minute >= start.minute)) ||
          (current.hour < end.hour ||
              (current.hour == end.hour && current.minute <= end.minute));
    }
  }

  /// Helper to convert time string (e.g., "09:00") to TimeOfDay
  /// Copied from UserService._timeOfDayFromString for testing
  static TimeOfDay _timeOfDayFromString(String timeString) {
    final parts = timeString.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }
}

/// Tests for pure logic functions from UserService
void main() {
  group('UserService time logic functions', () {
    group('isTimeInRange', () {
      test('time within normal range (9:00 to 17:00)', () {
        final current = TimeOfDay(hour: 12, minute: 30);
        expect(UserServiceTestHelper.isTimeInRange(current, '09:00', '17:00'), true);
      });

      test('time at start boundary is included', () {
        final current = TimeOfDay(hour: 9, minute: 0);
        expect(UserServiceTestHelper.isTimeInRange(current, '09:00', '17:00'), true);
      });

      test('time at end boundary is included', () {
        final current = TimeOfDay(hour: 17, minute: 0);
        expect(UserServiceTestHelper.isTimeInRange(current, '09:00', '17:00'), true);
      });

      test('time before start is excluded', () {
        final current = TimeOfDay(hour: 8, minute: 59);
        expect(UserServiceTestHelper.isTimeInRange(current, '09:00', '17:00'), false);
      });

      test('time after end is excluded', () {
        final current = TimeOfDay(hour: 17, minute: 1);
        expect(UserServiceTestHelper.isTimeInRange(current, '09:00', '17:00'), false);
      });

      test('overnight range - time in evening is included', () {
        final current = TimeOfDay(hour: 23, minute: 30);
        expect(UserServiceTestHelper.isTimeInRange(current, '22:00', '06:00'), true);
      });

      test('overnight range - time in morning is included', () {
        final current = TimeOfDay(hour: 3, minute: 30);
        expect(UserServiceTestHelper.isTimeInRange(current, '22:00', '06:00'), true);
      });

      test('overnight range - time in afternoon is excluded', () {
        final current = TimeOfDay(hour: 15, minute: 0);
        expect(UserServiceTestHelper.isTimeInRange(current, '22:00', '06:00'), false);
      });

      test('overnight range - time at evening start boundary', () {
        final current = TimeOfDay(hour: 22, minute: 0);
        expect(UserServiceTestHelper.isTimeInRange(current, '22:00', '06:00'), true);
      });

      test('overnight range - time at morning end boundary', () {
        final current = TimeOfDay(hour: 6, minute: 0);
        expect(UserServiceTestHelper.isTimeInRange(current, '22:00', '06:00'), true);
      });

      test('overnight range - time just before evening start', () {
        final current = TimeOfDay(hour: 21, minute: 59);
        expect(UserServiceTestHelper.isTimeInRange(current, '22:00', '06:00'), false);
      });

      test('overnight range - time just after morning end', () {
        final current = TimeOfDay(hour: 6, minute: 1);
        expect(UserServiceTestHelper.isTimeInRange(current, '22:00', '06:00'), false);
      });

      test('same start and end time', () {
        final current = TimeOfDay(hour: 12, minute: 0);
        // This edge case: start == end, actual behavior returns true (treats as valid range)
        expect(UserServiceTestHelper.isTimeInRange(current, '12:00', '12:00'), true);
      });

      test('handles minutes precisely in normal range', () {
        final current1 = TimeOfDay(hour: 9, minute: 29);
        final current2 = TimeOfDay(hour: 9, minute: 30);
        final current3 = TimeOfDay(hour: 9, minute: 31);
        
        expect(UserServiceTestHelper.isTimeInRange(current1, '09:30', '17:30'), false);
        expect(UserServiceTestHelper.isTimeInRange(current2, '09:30', '17:30'), true);
        expect(UserServiceTestHelper.isTimeInRange(current3, '09:30', '17:30'), true);
      });

      test('handles midnight edge case', () {
        final current = TimeOfDay(hour: 0, minute: 0);
        expect(UserServiceTestHelper.isTimeInRange(current, '23:00', '01:00'), true);
      });

      test('23:59 to 00:01 overnight range', () {
        final before = TimeOfDay(hour: 23, minute: 58);
        final start = TimeOfDay(hour: 23, minute: 59);
        final midnight = TimeOfDay(hour: 0, minute: 0);
        final end = TimeOfDay(hour: 0, minute: 1);
        final after = TimeOfDay(hour: 0, minute: 2);
        
        expect(UserServiceTestHelper.isTimeInRange(before, '23:59', '00:01'), false);
        expect(UserServiceTestHelper.isTimeInRange(start, '23:59', '00:01'), true);
        expect(UserServiceTestHelper.isTimeInRange(midnight, '23:59', '00:01'), true);
        expect(UserServiceTestHelper.isTimeInRange(end, '23:59', '00:01'), true);
        expect(UserServiceTestHelper.isTimeInRange(after, '23:59', '00:01'), false);
      });

      test('very short normal range (1 minute)', () {
        final current = TimeOfDay(hour: 12, minute: 30);
        expect(UserServiceTestHelper.isTimeInRange(current, '12:30', '12:31'), true);
      });

      test('very short overnight range (1 minute)', () {
        final current = TimeOfDay(hour: 23, minute: 59);
        expect(UserServiceTestHelper.isTimeInRange(current, '23:59', '00:00'), true);
      });

      test('noon boundaries', () {
        final beforeNoon = TimeOfDay(hour: 11, minute: 59);
        final noon = TimeOfDay(hour: 12, minute: 0);
        final afterNoon = TimeOfDay(hour: 12, minute: 1);
        
        expect(UserServiceTestHelper.isTimeInRange(beforeNoon, '12:00', '13:00'), false);
        expect(UserServiceTestHelper.isTimeInRange(noon, '12:00', '13:00'), true);
        expect(UserServiceTestHelper.isTimeInRange(afterNoon, '12:00', '13:00'), true);
      });
    });

    group('_timeOfDayFromString', () {
      test('parses standard time format', () {
        final result = UserServiceTestHelper._timeOfDayFromString('09:30');
        expect(result.hour, 9);
        expect(result.minute, 30);
      });

      test('parses midnight as 00:00', () {
        final result = UserServiceTestHelper._timeOfDayFromString('00:00');
        expect(result.hour, 0);
        expect(result.minute, 0);
      });

      test('parses 23:59', () {
        final result = UserServiceTestHelper._timeOfDayFromString('23:59');
        expect(result.hour, 23);
        expect(result.minute, 59);
      });

      test('parses noon as 12:00', () {
        final result = UserServiceTestHelper._timeOfDayFromString('12:00');
        expect(result.hour, 12);
        expect(result.minute, 0);
      });

      test('handles edge cases with boundaries', () {
        final testCases = [
          {'time': '00:00', 'hour': 0, 'minute': 0},
          {'time': '01:30', 'hour': 1, 'minute': 30},
          {'time': '12:00', 'hour': 12, 'minute': 0},
          {'time': '23:59', 'hour': 23, 'minute': 59},
        ];
        
        for (final testCase in testCases) {
          final result = UserServiceTestHelper._timeOfDayFromString(testCase['time'] as String);
          expect(result.hour, testCase['hour'], reason: 'Failed for ${testCase['time']}');
          expect(result.minute, testCase['minute'], reason: 'Failed for ${testCase['time']}');
        }
      });

      test('throws FormatException for invalid format', () {
        expect(
          () => UserServiceTestHelper._timeOfDayFromString('invalid'),
          throwsFormatException,
        );
      });

      test('throws FormatException for empty string', () {
        expect(
          () => UserServiceTestHelper._timeOfDayFromString(''),
          throwsA(isA<Exception>()),
        );
      });

      test('throws RangeError for partial time', () {
        expect(
          () => UserServiceTestHelper._timeOfDayFromString('12'),
          throwsA(isA<RangeError>()),
        );
      });
    });
  });
}