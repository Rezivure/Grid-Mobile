import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/models/room.dart';

void main() {
  group('Room.fromMap', () {
    test('parses valid map with JSON-encoded members', () {
      final map = {
        'roomId': '!abc:matrix.org',
        'name': 'Grid:Direct:@alice:matrix.org:@bob:matrix.org',
        'isGroup': 0,
        'lastActivity': '2026-01-01T00:00:00Z',
        'avatarUrl': null,
        'members': '["@alice:matrix.org","@bob:matrix.org"]',
        'expirationTimestamp': 0,
      };

      final room = Room.fromMap(map);

      expect(room.roomId, '!abc:matrix.org');
      expect(room.name, 'Grid:Direct:@alice:matrix.org:@bob:matrix.org');
      expect(room.isGroup, false);
      expect(room.members, ['@alice:matrix.org', '@bob:matrix.org']);
      expect(room.expirationTimestamp, 0);
      expect(room.avatarUrl, isNull);
    });

    test('parses isGroup=1 as true', () {
      final map = {
        'roomId': '!grp:matrix.org',
        'name': 'Grid:Group:0:TestGroup:@admin:matrix.org',
        'isGroup': 1,
        'lastActivity': '2026-01-01T00:00:00Z',
        'avatarUrl': 'mxc://example.com/avatar',
        'members': '["@alice:matrix.org"]',
        'expirationTimestamp': 1700000000,
      };

      final room = Room.fromMap(map);

      expect(room.isGroup, true);
      expect(room.avatarUrl, 'mxc://example.com/avatar');
      expect(room.expirationTimestamp, 1700000000);
    });

    test('handles corrupted members field (plain string, not JSON)', () {
      final map = {
        'roomId': '!corrupt:matrix.org',
        'name': 'Grid:Direct:@a:m.org:@b:m.org',
        'isGroup': 0,
        'lastActivity': '2026-01-01T00:00:00Z',
        'avatarUrl': null,
        'members': '@alice:matrix.org', // corrupted — not JSON array
        'expirationTimestamp': 0,
      };

      final room = Room.fromMap(map);

      // Should recover by wrapping in list
      expect(room.members, ['@alice:matrix.org']);
    });

    test('handles completely invalid members field gracefully', () {
      final map = {
        'roomId': '!bad:matrix.org',
        'name': 'Test',
        'isGroup': 0,
        'lastActivity': '2026-01-01T00:00:00Z',
        'avatarUrl': null,
        'members': 12345, // wrong type entirely
        'expirationTimestamp': 0,
      };

      // Should not throw — returns empty list
      final room = Room.fromMap(map);
      expect(room.members, isEmpty);
    });

    test('handles members as actual List (not string-encoded)', () {
      final map = {
        'roomId': '!list:matrix.org',
        'name': 'Test',
        'isGroup': 0,
        'lastActivity': '2026-01-01T00:00:00Z',
        'avatarUrl': null,
        'members': ['@alice:matrix.org', '@bob:matrix.org'],
        'expirationTimestamp': 0,
      };

      final room = Room.fromMap(map);
      expect(room.members, ['@alice:matrix.org', '@bob:matrix.org']);
    });

    test('handles empty JSON array members', () {
      final map = {
        'roomId': '!empty:matrix.org',
        'name': 'Test',
        'isGroup': 0,
        'lastActivity': '2026-01-01T00:00:00Z',
        'avatarUrl': null,
        'members': '[]',
        'expirationTimestamp': 0,
      };

      final room = Room.fromMap(map);
      expect(room.members, isEmpty);
    });
  });

  group('Room.toMap', () {
    test('serializes correctly with boolean to int conversion', () {
      final room = Room(
        roomId: '!abc:matrix.org',
        name: 'Grid:Direct:@a:m.org:@b:m.org',
        isGroup: false,
        lastActivity: '2026-01-01T00:00:00Z',
        avatarUrl: null,
        members: ['@a:m.org', '@b:m.org'],
        expirationTimestamp: 0,
      );

      final map = room.toMap();

      expect(map['isGroup'], 0);
      expect(map['members'], jsonEncode(['@a:m.org', '@b:m.org']));
      expect(map['avatarUrl'], isNull);
    });

    test('serializes group room correctly', () {
      final room = Room(
        roomId: '!grp:matrix.org',
        name: 'Grid:Group:1700000000:MyGroup:@admin:m.org',
        isGroup: true,
        lastActivity: '2026-01-01T00:00:00Z',
        avatarUrl: 'mxc://example.com/pic',
        members: ['@admin:m.org', '@user1:m.org'],
        expirationTimestamp: 1700000000,
      );

      final map = room.toMap();

      expect(map['isGroup'], 1);
      expect(map['expirationTimestamp'], 1700000000);
      expect(map['avatarUrl'], 'mxc://example.com/pic');
    });
  });

  group('Room JSON roundtrip', () {
    test('fromJson(toJson()) preserves all fields', () {
      final original = Room(
        roomId: '!roundtrip:matrix.org',
        name: 'Grid:Group:0:TestGroup:@creator:m.org',
        isGroup: true,
        lastActivity: '2026-02-14T10:00:00Z',
        avatarUrl: 'mxc://example.com/avatar',
        members: ['@creator:m.org', '@member1:m.org', '@member2:m.org'],
        expirationTimestamp: 1800000000,
      );

      final json = original.toJson();
      final restored = Room.fromJson(json);

      expect(restored.roomId, original.roomId);
      expect(restored.name, original.name);
      expect(restored.isGroup, original.isGroup);
      expect(restored.lastActivity, original.lastActivity);
      expect(restored.avatarUrl, original.avatarUrl);
      expect(restored.members, original.members);
      expect(restored.expirationTimestamp, original.expirationTimestamp);
    });

    test('roundtrip with null avatarUrl', () {
      final original = Room(
        roomId: '!null:matrix.org',
        name: 'Test',
        isGroup: false,
        lastActivity: '2026-01-01T00:00:00Z',
        avatarUrl: null,
        members: [],
        expirationTimestamp: 0,
      );

      final restored = Room.fromJson(original.toJson());
      expect(restored.avatarUrl, isNull);
    });
  });

  group('Room.copyWith', () {
    test('copies with overridden fields', () {
      final original = Room(
        roomId: '!abc:matrix.org',
        name: 'Original',
        isGroup: false,
        lastActivity: '2026-01-01T00:00:00Z',
        members: ['@a:m.org'],
        expirationTimestamp: 0,
      );

      final copied = original.copyWith(name: 'Updated', isGroup: true);

      expect(copied.name, 'Updated');
      expect(copied.isGroup, true);
      expect(copied.roomId, original.roomId); // unchanged
      expect(copied.members, original.members); // unchanged
    });

    test('copyWith creates independent members list', () {
      final original = Room(
        roomId: '!abc:matrix.org',
        name: 'Test',
        isGroup: false,
        lastActivity: '2026-01-01T00:00:00Z',
        members: ['@a:m.org'],
        expirationTimestamp: 0,
      );

      final copied = original.copyWith();
      copied.members.add('@b:m.org');

      expect(original.members, hasLength(1)); // original unmodified
      expect(copied.members, hasLength(2));
    });
  });
}
