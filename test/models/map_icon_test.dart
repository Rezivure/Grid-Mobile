import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/models/map_icon.dart';

void main() {
  MapIcon _makeIcon({
    String id = 'icon1',
    String roomId = '!room:matrix.org',
    String creatorId = '@alice:matrix.org',
    double latitude = 40.7128,
    double longitude = -74.0060,
    String iconType = 'icon',
    String iconData = 'pin',
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? expiresAt,
    Map<String, dynamic>? metadata,
  }) {
    return MapIcon(
      id: id,
      roomId: roomId,
      creatorId: creatorId,
      latitude: latitude,
      longitude: longitude,
      iconType: iconType,
      iconData: iconData,
      name: name,
      description: description,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      expiresAt: expiresAt,
      metadata: metadata,
    );
  }

  group('MapIcon constructor and getters', () {
    test('position getter returns correct LatLng', () {
      final icon = _makeIcon();
      expect(icon.position.latitude, 40.7128);
      expect(icon.position.longitude, -74.0060);
    });

    test('stores all fields correctly', () {
      final icon = _makeIcon(
        name: 'Meeting Point',
        description: 'By the fountain',
        metadata: {'color': 'red'},
      );
      expect(icon.name, 'Meeting Point');
      expect(icon.description, 'By the fountain');
      expect(icon.metadata, {'color': 'red'});
    });
  });

  group('MapIcon.fromJson', () {
    test('parses all fields', () {
      final json = {
        'id': 'icon1',
        'room_id': '!room:m.org',
        'creator_id': '@alice:m.org',
        'latitude': 40.0,
        'longitude': -74.0,
        'icon_type': 'icon',
        'icon_data': 'pin',
        'name': 'Test',
        'description': 'Desc',
        'created_at': '2026-01-01T00:00:00.000',
        'expires_at': '2026-02-01T00:00:00.000',
        'metadata': {'color': 'blue'},
      };
      final icon = MapIcon.fromJson(json);
      expect(icon.id, 'icon1');
      expect(icon.roomId, '!room:m.org');
      expect(icon.name, 'Test');
      expect(icon.expiresAt, isNotNull);
      expect(icon.metadata!['color'], 'blue');
    });

    test('handles null optional fields', () {
      final json = {
        'id': 'icon2',
        'room_id': '!room:m.org',
        'creator_id': '@bob:m.org',
        'latitude': 0.0,
        'longitude': 0.0,
        'icon_type': 'svg',
        'icon_data': '<svg/>',
        'name': null,
        'description': null,
        'created_at': '2026-01-01T00:00:00.000',
        'expires_at': null,
        'metadata': null,
      };
      final icon = MapIcon.fromJson(json);
      expect(icon.name, isNull);
      expect(icon.description, isNull);
      expect(icon.expiresAt, isNull);
      expect(icon.metadata, isNull);
    });
  });

  group('MapIcon.toJson', () {
    test('serializes all fields', () {
      final icon = _makeIcon(
        name: 'Test',
        description: 'Desc',
        expiresAt: DateTime(2026, 2, 1),
        metadata: {'size': 10},
      );
      final json = icon.toJson();
      expect(json['id'], 'icon1');
      expect(json['room_id'], '!room:matrix.org');
      expect(json['name'], 'Test');
      expect(json['expires_at'], isNotNull);
      expect(json['metadata'], {'size': 10});
    });

    test('serializes null fields as null', () {
      final icon = _makeIcon();
      final json = icon.toJson();
      expect(json['name'], isNull);
      expect(json['description'], isNull);
      expect(json['expires_at'], isNull);
      expect(json['metadata'], isNull);
    });
  });

  group('MapIcon JSON roundtrip', () {
    test('fromJson(toJson()) preserves all fields', () {
      final original = _makeIcon(
        name: 'Roundtrip',
        description: 'Test',
        expiresAt: DateTime(2026, 6, 15),
        metadata: {'color': 'green', 'radius': 100},
      );
      final restored = MapIcon.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.roomId, original.roomId);
      expect(restored.creatorId, original.creatorId);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.iconType, original.iconType);
      expect(restored.iconData, original.iconData);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
    });

    test('roundtrip with no optional fields', () {
      final original = _makeIcon();
      final restored = MapIcon.fromJson(original.toJson());
      expect(restored.name, isNull);
      expect(restored.expiresAt, isNull);
      expect(restored.metadata, isNull);
    });
  });

  group('MapIcon.fromDatabase', () {
    test('parses database map', () {
      final map = {
        'id': 'db1',
        'room_id': '!room:m.org',
        'creator_id': '@alice:m.org',
        'latitude': 51.5074,
        'longitude': -0.1278,
        'icon_type': 'icon',
        'icon_data': 'star',
        'name': 'London',
        'description': null,
        'created_at': '2026-01-01T00:00:00.000',
        'expires_at': null,
        'metadata': null,
      };
      final icon = MapIcon.fromDatabase(map);
      expect(icon.id, 'db1');
      expect(icon.latitude, 51.5074);
    });
  });

  group('MapIcon.toDatabase', () {
    test('serializes metadata as string', () {
      final icon = _makeIcon(metadata: {'key': 'value'});
      final db = icon.toDatabase();
      expect(db['metadata'], isA<String>());
    });

    test('null metadata stays null', () {
      final icon = _makeIcon();
      final db = icon.toDatabase();
      expect(db['metadata'], isNull);
    });
  });
}
