import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';
import 'package:grid_frontend/models/sharing_window.dart';

void main() {
  group('SharingPreferences.toMap', () {
    test('converts activeSharing bool to int', () {
      final prefs = SharingPreferences(
        targetId: '@alice:matrix.org',
        targetType: 'user',
        activeSharing: true,
      );
      expect(prefs.toMap()['activeSharing'], 1);
    });

    test('converts false activeSharing to 0', () {
      final prefs = SharingPreferences(
        targetId: '@alice:matrix.org',
        targetType: 'user',
        activeSharing: false,
      );
      expect(prefs.toMap()['activeSharing'], 0);
    });

    test('encodes shareWindows as JSON string', () {
      final prefs = SharingPreferences(
        targetId: '@alice:matrix.org',
        targetType: 'user',
        activeSharing: true,
        shareWindows: [
          SharingWindow(label: 'Test', days: [0], isAllDay: true, isActive: true),
        ],
      );
      final map = prefs.toMap();
      expect(map['sharePeriods'], isA<String>());
      final decoded = jsonDecode(map['sharePeriods']);
      expect(decoded, isList);
      expect(decoded.length, 1);
    });

    test('null shareWindows produces null sharePeriods', () {
      final prefs = SharingPreferences(
        targetId: '@bob:matrix.org',
        targetType: 'group',
        activeSharing: false,
      );
      expect(prefs.toMap()['sharePeriods'], isNull);
    });

    test('includes id when present', () {
      final prefs = SharingPreferences(
        id: 42,
        targetId: '@alice:matrix.org',
        targetType: 'user',
        activeSharing: true,
      );
      expect(prefs.toMap()['id'], 42);
    });

    test('id is null when not provided', () {
      final prefs = SharingPreferences(
        targetId: '@alice:matrix.org',
        targetType: 'user',
        activeSharing: true,
      );
      expect(prefs.toMap()['id'], isNull);
    });
  });

  group('SharingPreferences.fromMap', () {
    test('parses activeSharing int to bool', () {
      final prefs = SharingPreferences.fromMap({
        'id': 1,
        'targetId': '@alice:matrix.org',
        'targetType': 'user',
        'activeSharing': 1,
        'sharePeriods': null,
      });
      expect(prefs.activeSharing, true);
    });

    test('parses 0 as false', () {
      final prefs = SharingPreferences.fromMap({
        'id': 1,
        'targetId': '@alice:matrix.org',
        'targetType': 'user',
        'activeSharing': 0,
        'sharePeriods': null,
      });
      expect(prefs.activeSharing, false);
    });

    test('parses sharePeriods JSON', () {
      final windows = [
        SharingWindow(label: 'Work', days: [0, 1, 2], isAllDay: false, isActive: true, startTime: '09:00', endTime: '17:00'),
      ];
      final prefs = SharingPreferences.fromMap({
        'id': 1,
        'targetId': '@alice:matrix.org',
        'targetType': 'user',
        'activeSharing': 1,
        'sharePeriods': jsonEncode(windows.map((w) => w.toJson()).toList()),
      });
      expect(prefs.shareWindows, hasLength(1));
      expect(prefs.shareWindows!.first.label, 'Work');
      expect(prefs.shareWindows!.first.days, [0, 1, 2]);
    });

    test('empty sharePeriods string results in null windows', () {
      final prefs = SharingPreferences.fromMap({
        'id': 1,
        'targetId': '@alice:matrix.org',
        'targetType': 'user',
        'activeSharing': 1,
        'sharePeriods': '',
      });
      expect(prefs.shareWindows, isNull);
    });

    test('multiple windows roundtrip', () {
      final windows = [
        SharingWindow(label: 'Morning', days: [0, 1], isAllDay: false, isActive: true, startTime: '06:00', endTime: '12:00'),
        SharingWindow(label: 'Evening', days: [2, 3], isAllDay: false, isActive: false, startTime: '18:00', endTime: '22:00'),
      ];
      final prefs = SharingPreferences(
        id: 5,
        targetId: '!room:matrix.org',
        targetType: 'group',
        activeSharing: true,
        shareWindows: windows,
      );
      final restored = SharingPreferences.fromMap(prefs.toMap());
      expect(restored.shareWindows, hasLength(2));
      expect(restored.shareWindows![0].label, 'Morning');
      expect(restored.shareWindows![1].isActive, false);
    });
  });
}
