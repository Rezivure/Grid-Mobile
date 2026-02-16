import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/models/map_icon.dart';

void main() {
  group('MapIcon', () {
    MapIcon makeIcon({
      String id = 'icon1',
      String roomId = 'room1',
      String creatorId = 'user1',
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
        createdAt: createdAt ?? DateTime(2024, 1, 1),
        expiresAt: expiresAt,
        metadata: metadata,
      );
    }

    group('position getter', () {
      test('returns correct LatLng', () {
        final icon = makeIcon(latitude: 40.7128, longitude: -74.0060);
        expect(icon.position.latitude, closeTo(40.7128, 0.0001));
        expect(icon.position.longitude, closeTo(-74.0060, 0.0001));
      });

      test('handles zero coordinates', () {
        final icon = makeIcon(latitude: 0.0, longitude: 0.0);
        expect(icon.position.latitude, 0.0);
        expect(icon.position.longitude, 0.0);
      });

      test('handles negative coordinates', () {
        final icon = makeIcon(latitude: -33.8688, longitude: 151.2093);
        expect(icon.position.latitude, closeTo(-33.8688, 0.0001));
        expect(icon.position.longitude, closeTo(151.2093, 0.0001));
      });
    });

    group('fromJson / toJson roundtrip', () {
      test('basic icon', () {
        final icon = makeIcon(name: 'Test', description: 'Desc');
        final json = icon.toJson();
        final restored = MapIcon.fromJson(json);
        expect(restored.id, icon.id);
        expect(restored.roomId, icon.roomId);
        expect(restored.creatorId, icon.creatorId);
        expect(restored.latitude, icon.latitude);
        expect(restored.longitude, icon.longitude);
        expect(restored.iconType, icon.iconType);
        expect(restored.iconData, icon.iconData);
        expect(restored.name, 'Test');
        expect(restored.description, 'Desc');
      });

      test('icon with metadata', () {
        final icon = makeIcon(metadata: {'color': 'red', 'size': 24});
        final json = icon.toJson();
        final restored = MapIcon.fromJson(json);
        expect(restored.metadata, isNotNull);
        expect(restored.metadata!['color'], 'red');
        expect(restored.metadata!['size'], 24);
      });

      test('icon with expiration', () {
        final expires = DateTime(2024, 12, 31);
        final icon = makeIcon(expiresAt: expires);
        final json = icon.toJson();
        final restored = MapIcon.fromJson(json);
        expect(restored.expiresAt, isNotNull);
        expect(restored.expiresAt!.year, 2024);
        expect(restored.expiresAt!.month, 12);
      });

      test('icon without optional fields', () {
        final icon = makeIcon();
        final json = icon.toJson();
        final restored = MapIcon.fromJson(json);
        expect(restored.name, isNull);
        expect(restored.description, isNull);
        expect(restored.expiresAt, isNull);
        expect(restored.metadata, isNull);
      });
    });

    group('fromDatabase / toDatabase', () {
      test('basic roundtrip', () {
        final icon = makeIcon(name: 'DB Test');
        final dbMap = icon.toDatabase();
        final restored = MapIcon.fromDatabase(dbMap);
        expect(restored.id, icon.id);
        expect(restored.name, 'DB Test');
      });

      test('handles null metadata in database', () {
        final dbMap = {
          'id': 'icon1',
          'room_id': 'room1',
          'creator_id': 'user1',
          'latitude': 40.0,
          'longitude': -74.0,
          'icon_type': 'icon',
          'icon_data': 'pin',
          'name': null,
          'description': null,
          'created_at': '2024-01-01T00:00:00.000',
          'expires_at': null,
          'metadata': null,
        };
        final icon = MapIcon.fromDatabase(dbMap);
        expect(icon.metadata, isNull);
      });

      test('toDatabase includes all fields', () {
        final icon = makeIcon(
          name: 'Test',
          description: 'A description',
          expiresAt: DateTime(2024, 12, 31),
        );
        final db = icon.toDatabase();
        expect(db['id'], 'icon1');
        expect(db['room_id'], 'room1');
        expect(db['creator_id'], 'user1');
        expect(db['latitude'], closeTo(40.7128, 0.001));
        expect(db['longitude'], closeTo(-74.006, 0.001));
        expect(db['icon_type'], 'icon');
        expect(db['icon_data'], 'pin');
        expect(db['name'], 'Test');
        expect(db['description'], 'A description');
        expect(db['expires_at'], isNotNull);
      });

      test('toJson includes all required fields', () {
        final icon = makeIcon();
        final json = icon.toJson();
        expect(json.containsKey('id'), isTrue);
        expect(json.containsKey('room_id'), isTrue);
        expect(json.containsKey('creator_id'), isTrue);
        expect(json.containsKey('latitude'), isTrue);
        expect(json.containsKey('longitude'), isTrue);
        expect(json.containsKey('icon_type'), isTrue);
        expect(json.containsKey('icon_data'), isTrue);
        expect(json.containsKey('created_at'), isTrue);
      });
    });

    group('SVG icon type', () {
      test('stores SVG data', () {
        final icon = makeIcon(iconType: 'svg', iconData: '<svg></svg>');
        expect(icon.iconType, 'svg');
        expect(icon.iconData, '<svg></svg>');
        final json = icon.toJson();
        final restored = MapIcon.fromJson(json);
        expect(restored.iconType, 'svg');
        expect(restored.iconData, '<svg></svg>');
      });
    });
  });
}
