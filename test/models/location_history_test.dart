import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/models/location_history.dart';

void main() {
  group('LocationPoint', () {
    test('constructor stores fields', () {
      final point = LocationPoint(
        latitude: 40.7128,
        longitude: -74.0060,
        timestamp: DateTime(2026, 1, 1),
        accuracy: 'high',
      );
      expect(point.latitude, 40.7128);
      expect(point.longitude, -74.0060);
      expect(point.accuracy, 'high');
    });

    test('toJson includes all fields', () {
      final point = LocationPoint(
        latitude: 40.0,
        longitude: -74.0,
        timestamp: DateTime(2026, 1, 1),
        accuracy: '10m',
      );
      final json = point.toJson();
      expect(json['latitude'], 40.0);
      expect(json['longitude'], -74.0);
      expect(json['timestamp'], isA<String>());
      expect(json['accuracy'], '10m');
    });

    test('toJson omits null accuracy', () {
      final point = LocationPoint(
        latitude: 0.0,
        longitude: 0.0,
        timestamp: DateTime(2026, 1, 1),
      );
      final json = point.toJson();
      expect(json.containsKey('accuracy'), false);
    });

    test('fromJson parses correctly', () {
      final json = {
        'latitude': 51.5074,
        'longitude': -0.1278,
        'timestamp': '2026-01-15T12:00:00.000',
        'accuracy': '5m',
      };
      final point = LocationPoint.fromJson(json);
      expect(point.latitude, 51.5074);
      expect(point.longitude, -0.1278);
      expect(point.accuracy, '5m');
    });

    test('fromJson with null accuracy', () {
      final json = {
        'latitude': 0.0,
        'longitude': 0.0,
        'timestamp': '2026-01-01T00:00:00.000',
      };
      final point = LocationPoint.fromJson(json);
      expect(point.accuracy, isNull);
    });

    test('JSON roundtrip preserves data', () {
      final original = LocationPoint(
        latitude: -33.8688,
        longitude: 151.2093,
        timestamp: DateTime(2026, 6, 15, 14, 30),
        accuracy: 'medium',
      );
      final restored = LocationPoint.fromJson(original.toJson());
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.accuracy, original.accuracy);
    });
  });

  group('LocationHistory', () {
    test('constructor stores fields', () {
      final history = LocationHistory(
        userId: '@alice:matrix.org',
        points: [],
        lastUpdated: DateTime(2026, 1, 1),
      );
      expect(history.userId, '@alice:matrix.org');
      expect(history.points, isEmpty);
    });

    test('toJson serializes points', () {
      final history = LocationHistory(
        userId: '@alice:matrix.org',
        points: [
          LocationPoint(latitude: 40.0, longitude: -74.0, timestamp: DateTime(2026, 1, 1)),
          LocationPoint(latitude: 41.0, longitude: -73.0, timestamp: DateTime(2026, 1, 2)),
        ],
        lastUpdated: DateTime(2026, 1, 2),
      );
      final json = history.toJson();
      expect(json['userId'], '@alice:matrix.org');
      expect(json['points'], hasLength(2));
    });

    test('fromJson parses correctly', () {
      final json = {
        'userId': '@bob:matrix.org',
        'points': [
          {'latitude': 40.0, 'longitude': -74.0, 'timestamp': '2026-01-01T00:00:00.000'},
        ],
        'lastUpdated': '2026-01-01T00:00:00.000',
      };
      final history = LocationHistory.fromJson(json);
      expect(history.userId, '@bob:matrix.org');
      expect(history.points, hasLength(1));
      expect(history.points.first.latitude, 40.0);
    });

    test('JSON roundtrip preserves data', () {
      final original = LocationHistory(
        userId: '@test:matrix.org',
        points: [
          LocationPoint(latitude: 10.0, longitude: 20.0, timestamp: DateTime(2026, 1, 1), accuracy: 'high'),
          LocationPoint(latitude: 11.0, longitude: 21.0, timestamp: DateTime(2026, 1, 2)),
        ],
        lastUpdated: DateTime(2026, 1, 2),
      );
      final restored = LocationHistory.fromJson(original.toJson());
      expect(restored.userId, original.userId);
      expect(restored.points.length, original.points.length);
      expect(restored.points[0].latitude, original.points[0].latitude);
      expect(restored.points[0].accuracy, 'high');
      expect(restored.points[1].accuracy, isNull);
    });

    test('empty points list', () {
      final history = LocationHistory(
        userId: '@empty:matrix.org',
        points: [],
        lastUpdated: DateTime(2026, 1, 1),
      );
      final restored = LocationHistory.fromJson(history.toJson());
      expect(restored.points, isEmpty);
    });
  });

  group('LocationHistoryConfig', () {
    test('constants are reasonable', () {
      expect(LocationHistoryConfig.maxDaysToStore, 7);
      expect(LocationHistoryConfig.minSecondsBetweenPoints, 180);
      expect(LocationHistoryConfig.minDistanceMeters, 50.0);
      expect(LocationHistoryConfig.maxPointsPerUser, 3360);
    });
  });
}
