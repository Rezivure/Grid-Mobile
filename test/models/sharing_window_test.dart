import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/models/sharing_window.dart';

void main() {
  group('SharingWindow.fromJson', () {
    test('parses all fields', () {
      final window = SharingWindow.fromJson({
        'label': 'Work',
        'days': [0, 1, 2, 3, 4],
        'isAllDay': false,
        'startTime': '09:00',
        'endTime': '17:00',
        'isActive': true,
      });
      expect(window.label, 'Work');
      expect(window.days, [0, 1, 2, 3, 4]);
      expect(window.isAllDay, false);
      expect(window.startTime, '09:00');
      expect(window.endTime, '17:00');
      expect(window.isActive, true);
    });

    test('missing isActive defaults to true', () {
      final window = SharingWindow.fromJson({
        'label': 'Test',
        'days': [0],
        'isAllDay': true,
        'startTime': null,
        'endTime': null,
      });
      expect(window.isActive, true);
    });

    test('isActive false is preserved', () {
      final window = SharingWindow.fromJson({
        'label': 'Disabled',
        'days': [5, 6],
        'isAllDay': true,
        'isActive': false,
      });
      expect(window.isActive, false);
    });

    test('empty days list', () {
      final window = SharingWindow.fromJson({
        'label': 'Never',
        'days': [],
        'isAllDay': true,
        'isActive': true,
      });
      expect(window.days, isEmpty);
    });

    test('all seven days', () {
      final window = SharingWindow.fromJson({
        'label': 'Every Day',
        'days': [0, 1, 2, 3, 4, 5, 6],
        'isAllDay': true,
        'isActive': true,
      });
      expect(window.days, hasLength(7));
    });
  });

  group('SharingWindow.toJson', () {
    test('serializes all fields', () {
      final window = SharingWindow(
        label: 'Work',
        days: [0, 1, 2],
        isAllDay: false,
        isActive: true,
        startTime: '09:00',
        endTime: '17:00',
      );
      final json = window.toJson();
      expect(json['label'], 'Work');
      expect(json['days'], [0, 1, 2]);
      expect(json['isAllDay'], false);
      expect(json['isActive'], true);
      expect(json['startTime'], '09:00');
      expect(json['endTime'], '17:00');
    });

    test('all-day window has null times', () {
      final window = SharingWindow(
        label: 'Always',
        days: [0, 1, 2, 3, 4, 5, 6],
        isAllDay: true,
        isActive: true,
      );
      final json = window.toJson();
      expect(json['startTime'], isNull);
      expect(json['endTime'], isNull);
    });
  });

  group('SharingWindow roundtrip', () {
    test('fromJson(toJson()) preserves all fields', () {
      final original = SharingWindow(
        label: 'Weekend',
        days: [5, 6],
        isAllDay: false,
        isActive: false,
        startTime: '10:00',
        endTime: '22:00',
      );
      final restored = SharingWindow.fromJson(original.toJson());
      expect(restored.label, original.label);
      expect(restored.days, original.days);
      expect(restored.isAllDay, original.isAllDay);
      expect(restored.isActive, original.isActive);
      expect(restored.startTime, original.startTime);
      expect(restored.endTime, original.endTime);
    });
  });
}
