import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/models/grid_user.dart';

void main() {
  group('GridUser.fromMap', () {
    test('parses all fields', () {
      final user = GridUser.fromMap({
        'userId': '@alice:matrix.org',
        'displayName': 'Alice',
        'avatarUrl': 'mxc://example.com/abc',
        'lastSeen': '2026-01-01T00:00:00Z',
        'profileStatus': 'Hello!',
      });
      expect(user.userId, '@alice:matrix.org');
      expect(user.displayName, 'Alice');
      expect(user.avatarUrl, 'mxc://example.com/abc');
      expect(user.lastSeen, '2026-01-01T00:00:00Z');
      expect(user.profileStatus, 'Hello!');
    });

    test('handles null optional fields', () {
      final user = GridUser.fromMap({
        'userId': '@bob:matrix.org',
        'displayName': null,
        'avatarUrl': null,
        'lastSeen': '2026-01-01T00:00:00Z',
        'profileStatus': null,
      });
      expect(user.displayName, isNull);
      expect(user.avatarUrl, isNull);
      expect(user.profileStatus, isNull);
    });
  });

  group('GridUser.toMap', () {
    test('serializes correctly', () {
      final user = GridUser(
        userId: '@alice:matrix.org',
        displayName: 'Alice',
        avatarUrl: 'mxc://example.com/abc',
        lastSeen: '2026-01-01T00:00:00Z',
        profileStatus: 'Hello!',
      );
      final map = user.toMap();
      expect(map['userId'], '@alice:matrix.org');
      expect(map['displayName'], 'Alice');
      expect(map['avatarUrl'], 'mxc://example.com/abc');
      expect(map['profileStatus'], 'Hello!');
    });

    test('serializes null fields as null', () {
      final user = GridUser(
        userId: '@bob:matrix.org',
        lastSeen: '2026-01-01T00:00:00Z',
      );
      final map = user.toMap();
      expect(map['displayName'], isNull);
      expect(map['avatarUrl'], isNull);
      expect(map['profileStatus'], isNull);
    });
  });

  group('GridUser JSON roundtrip', () {
    test('fromJson(toJson()) preserves all fields', () {
      final original = GridUser(
        userId: '@test:matrix.org',
        displayName: 'Test User',
        avatarUrl: 'mxc://example.com/pic',
        lastSeen: '2026-02-14T10:00:00Z',
        profileStatus: 'Testing',
      );
      final restored = GridUser.fromJson(original.toJson());
      expect(restored.userId, original.userId);
      expect(restored.displayName, original.displayName);
      expect(restored.avatarUrl, original.avatarUrl);
      expect(restored.lastSeen, original.lastSeen);
      expect(restored.profileStatus, original.profileStatus);
    });

    test('roundtrip with null optional fields', () {
      final original = GridUser(
        userId: '@minimal:matrix.org',
        lastSeen: '2026-01-01T00:00:00Z',
      );
      final restored = GridUser.fromJson(original.toJson());
      expect(restored.displayName, isNull);
      expect(restored.avatarUrl, isNull);
      expect(restored.profileStatus, isNull);
    });

    test('toJson produces valid JSON string', () {
      final user = GridUser(
        userId: '@alice:matrix.org',
        lastSeen: '2026-01-01T00:00:00Z',
      );
      expect(() => jsonDecode(user.toJson()), returnsNormally);
    });
  });

  group('GridUser edge cases', () {
    test('special characters in displayName', () {
      final user = GridUser(
        userId: '@special:matrix.org',
        displayName: 'Alice "Bob" <script>',
        lastSeen: '2026-01-01T00:00:00Z',
      );
      final restored = GridUser.fromJson(user.toJson());
      expect(restored.displayName, 'Alice "Bob" <script>');
    });

    test('empty string fields', () {
      final user = GridUser(
        userId: '@empty:matrix.org',
        displayName: '',
        avatarUrl: '',
        lastSeen: '',
        profileStatus: '',
      );
      final map = user.toMap();
      expect(map['displayName'], '');
      expect(map['avatarUrl'], '');
    });

    test('unicode in displayName', () {
      final user = GridUser(
        userId: '@unicode:matrix.org',
        displayName: '日本語テスト 🎉',
        lastSeen: '2026-01-01T00:00:00Z',
      );
      final restored = GridUser.fromJson(user.toJson());
      expect(restored.displayName, '日本語テスト 🎉');
    });
  });
}
