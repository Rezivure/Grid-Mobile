import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/models/sharing_window.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';

/// We can't directly call UserService.isTimeInRange without a UserService instance
/// (it requires Client, repos, etc.). Instead we replicate the pure logic here
/// and test it. When the method is extracted to a utility, these tests transfer directly.
///
/// The logic from UserService:
bool isTimeInRange(TimeOfDay current, String startTime, String endTime) {
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

TimeOfDay _timeOfDayFromString(String timeString) {
  final parts = timeString.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

void main() {
  group('isTimeInRange — normal range (09:00-17:00)', () {
    test('time inside range returns true', () {
      expect(isTimeInRange(const TimeOfDay(hour: 12, minute: 0), '09:00', '17:00'), true);
    });

    test('time at start boundary returns true', () {
      expect(isTimeInRange(const TimeOfDay(hour: 9, minute: 0), '09:00', '17:00'), true);
    });

    test('time at end boundary returns true', () {
      expect(isTimeInRange(const TimeOfDay(hour: 17, minute: 0), '09:00', '17:00'), true);
    });

    test('time before range returns false', () {
      expect(isTimeInRange(const TimeOfDay(hour: 8, minute: 59), '09:00', '17:00'), false);
    });

    test('time after range returns false', () {
      expect(isTimeInRange(const TimeOfDay(hour: 17, minute: 1), '09:00', '17:00'), false);
    });
  });

  group('isTimeInRange — overnight range (22:00-06:00)', () {
    test('time late at night (23:00) returns true', () {
      expect(isTimeInRange(const TimeOfDay(hour: 23, minute: 0), '22:00', '06:00'), true);
    });

    test('time early morning (03:00) returns true', () {
      expect(isTimeInRange(const TimeOfDay(hour: 3, minute: 0), '22:00', '06:00'), true);
    });

    test('time at start boundary (22:00) returns true', () {
      expect(isTimeInRange(const TimeOfDay(hour: 22, minute: 0), '22:00', '06:00'), true);
    });

    test('time at end boundary (06:00) returns true', () {
      expect(isTimeInRange(const TimeOfDay(hour: 6, minute: 0), '22:00', '06:00'), true);
    });

    test('time during day (12:00) returns false', () {
      expect(isTimeInRange(const TimeOfDay(hour: 12, minute: 0), '22:00', '06:00'), false);
    });

    test('time just before start (21:59) returns false', () {
      expect(isTimeInRange(const TimeOfDay(hour: 21, minute: 59), '22:00', '06:00'), false);
    });

    test('time just after end (06:01) returns false', () {
      expect(isTimeInRange(const TimeOfDay(hour: 6, minute: 1), '22:00', '06:00'), false);
    });
  });

  group('isTimeInRange — edge cases', () {
    test('midnight range (00:00-00:00) — same start/end treats as overnight', () {
      // When start == end, the "normal range" branch won't trigger (start < end is false)
      // so it falls through to overnight logic, which is always true
      expect(isTimeInRange(const TimeOfDay(hour: 12, minute: 0), '00:00', '00:00'), true);
    });

    test('narrow range (10:00-10:30)', () {
      expect(isTimeInRange(const TimeOfDay(hour: 10, minute: 15), '10:00', '10:30'), true);
      expect(isTimeInRange(const TimeOfDay(hour: 10, minute: 31), '10:00', '10:30'), false);
    });
  });

  group('SharingWindow model', () {
    test('fromJson/toJson roundtrip', () {
      final original = SharingWindow(
        label: 'Work Hours',
        days: [0, 1, 2, 3, 4], // Mon-Fri
        isAllDay: false,
        isActive: true,
        startTime: '09:00',
        endTime: '17:00',
      );

      final json = original.toJson();
      final restored = SharingWindow.fromJson(json);

      expect(restored.label, 'Work Hours');
      expect(restored.days, [0, 1, 2, 3, 4]);
      expect(restored.isAllDay, false);
      expect(restored.isActive, true);
      expect(restored.startTime, '09:00');
      expect(restored.endTime, '17:00');
    });

    test('missing isActive defaults to true', () {
      final json = {
        'label': 'Test',
        'days': [0],
        'isAllDay': true,
        'startTime': null,
        'endTime': null,
        // isActive intentionally omitted
      };

      final window = SharingWindow.fromJson(json);
      expect(window.isActive, true);
    });

    test('all-day window', () {
      final window = SharingWindow(
        label: 'Always',
        days: [0, 1, 2, 3, 4, 5, 6],
        isAllDay: true,
        isActive: true,
      );

      final json = window.toJson();
      expect(json['isAllDay'], true);
      expect(json['startTime'], isNull);
      expect(json['endTime'], isNull);
    });
  });

  group('SharingPreferences model', () {
    test('fromMap/toMap roundtrip with windows', () {
      final original = SharingPreferences(
        id: 1,
        targetId: '@alice:matrix.org',
        targetType: 'user',
        activeSharing: true,
        shareWindows: [
          SharingWindow(
            label: 'Work',
            days: [0, 1, 2, 3, 4],
            isAllDay: false,
            isActive: true,
            startTime: '09:00',
            endTime: '17:00',
          ),
        ],
      );

      final map = original.toMap();
      expect(map['activeSharing'], 1);
      expect(map['sharePeriods'], isA<String>());

      final restored = SharingPreferences.fromMap(map);
      expect(restored.targetId, '@alice:matrix.org');
      expect(restored.targetType, 'user');
      expect(restored.activeSharing, true);
      expect(restored.shareWindows, hasLength(1));
      expect(restored.shareWindows!.first.label, 'Work');
    });

    test('fromMap with null sharePeriods', () {
      final map = {
        'id': 2,
        'targetId': '!room:matrix.org',
        'targetType': 'group',
        'activeSharing': 0,
        'sharePeriods': null,
      };

      final prefs = SharingPreferences.fromMap(map);
      expect(prefs.activeSharing, false);
      expect(prefs.shareWindows, isNull);
    });

    test('fromMap with empty sharePeriods string', () {
      final map = {
        'id': 3,
        'targetId': '@bob:matrix.org',
        'targetType': 'contact',
        'activeSharing': 1,
        'sharePeriods': '',
      };

      final prefs = SharingPreferences.fromMap(map);
      expect(prefs.shareWindows, isNull);
    });
  });
}
