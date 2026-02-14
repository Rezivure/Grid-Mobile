import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/models/user_location.dart';

/// UserLocation depends on encryption for fromMap/toMap, so we only test
/// the constructor and pure getters here. Encryption roundtrip tests
/// belong in a separate encryption_utils_test.dart with known keys.
void main() {
  group('UserLocation constructor and getters', () {
    test('position getter returns correct LatLng', () {
      final loc = UserLocation(
        userId: '@alice:matrix.org',
        latitude: 40.7128,
        longitude: -74.0060,
        timestamp: '2026-01-01T00:00:00Z',
        iv: 'dGVzdGl2MTIzNDU2Nzg=', // dummy base64
      );

      expect(loc.position.latitude, 40.7128);
      expect(loc.position.longitude, -74.0060);
    });

    test('stores all fields correctly', () {
      final loc = UserLocation(
        userId: '@bob:matrix.org',
        latitude: 0.0,
        longitude: 0.0,
        timestamp: '2026-02-14T12:00:00Z',
        iv: 'YWJjZGVmZ2hpamtsbW5v',
      );

      expect(loc.userId, '@bob:matrix.org');
      expect(loc.timestamp, '2026-02-14T12:00:00Z');
      expect(loc.latitude, 0.0);
      expect(loc.longitude, 0.0);
    });

    test('handles extreme coordinates', () {
      final loc = UserLocation(
        userId: '@polar:matrix.org',
        latitude: 90.0,
        longitude: 180.0,
        timestamp: '2026-01-01T00:00:00Z',
        iv: 'dGVzdA==',
      );

      expect(loc.position.latitude, 90.0);
      expect(loc.position.longitude, 180.0);
    });

    test('handles negative coordinates', () {
      final loc = UserLocation(
        userId: '@south:matrix.org',
        latitude: -33.8688,
        longitude: -151.2093,
        timestamp: '2026-01-01T00:00:00Z',
        iv: 'dGVzdA==',
      );

      expect(loc.position.latitude, closeTo(-33.8688, 0.0001));
      expect(loc.position.longitude, closeTo(-151.2093, 0.0001));
    });
  });
}
