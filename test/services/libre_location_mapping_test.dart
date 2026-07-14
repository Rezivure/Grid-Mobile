import 'package:flutter_test/flutter_test.dart';
import 'package:libre_location/libre_location.dart' as libre;
import 'package:grid_frontend/services/location/libre_location_service.dart';

/// Unit tests for [mapPositionToLocationUpdate], the pure mapping shared by
/// the position and heartbeat stream paths in LibreLocationService.
///
/// The heartbeat path is what fixes #282 ("location does not periodically
/// update"): when a device is stationary the plugin pauses GPS and only emits
/// heartbeat events carrying the last known Position, so the mapping must
/// faithfully carry every field through for a re-broadcast to be correct.
void main() {
  final ts = DateTime.fromMillisecondsSinceEpoch(1720000000000);

  group('mapPositionToLocationUpdate', () {
    test('carries core coordinate and motion fields through', () {
      final pos = libre.Position(
        latitude: 40.7128,
        longitude: -74.0060,
        altitude: 12.5,
        accuracy: 8.0,
        speed: 1.4,
        heading: 270.0,
        timestamp: ts,
        isMoving: true,
      );

      final update = mapPositionToLocationUpdate(pos);

      expect(update.latitude, 40.7128);
      expect(update.longitude, -74.0060);
      expect(update.altitude, 12.5);
      expect(update.accuracy, 8.0);
      expect(update.speed, 1.4);
      expect(update.heading, 270.0);
      expect(update.timestamp, ts);
      expect(update.isMoving, true);
    });

    test('maps a stationary heartbeat position (isMoving false)', () {
      // A heartbeat while parked: same last-known fix, not moving. This is
      // exactly the payload that must still re-broadcast for #282.
      final pos = libre.Position(
        latitude: 51.5074,
        longitude: -0.1278,
        timestamp: ts,
        isMoving: false,
      );

      final update = mapPositionToLocationUpdate(pos);

      expect(update.latitude, 51.5074);
      expect(update.longitude, -0.1278);
      expect(update.isMoving, false);
    });

    test('surfaces battery level and charging state when present', () {
      final pos = libre.Position(
        latitude: 1.0,
        longitude: 2.0,
        timestamp: ts,
        battery: const libre.BatteryInfo(level: 0.42, isCharging: true),
      );

      final update = mapPositionToLocationUpdate(pos);

      expect(update.batteryLevel, 0.42);
      expect(update.isCharging, true);
    });

    test('leaves battery fields null when the plugin omits battery', () {
      final pos = libre.Position(
        latitude: 1.0,
        longitude: 2.0,
        timestamp: ts,
      );

      final update = mapPositionToLocationUpdate(pos);

      expect(update.batteryLevel, isNull);
      expect(update.isCharging, isNull);
    });

    test('a HeartbeatEvent position round-trips through the mapping', () {
      // Mirrors the live-stream heartbeat path: HeartbeatEvent -> position ->
      // LocationUpdate for re-broadcast.
      final event = libre.HeartbeatEvent(
        position: libre.Position(
          latitude: 35.6762,
          longitude: 139.6503,
          accuracy: 15.0,
          timestamp: ts,
          isMoving: false,
        ),
      );

      final update = mapPositionToLocationUpdate(event.position);

      expect(update.latitude, 35.6762);
      expect(update.longitude, 139.6503);
      expect(update.accuracy, 15.0);
      expect(update.isMoving, false);
    });
  });
}
