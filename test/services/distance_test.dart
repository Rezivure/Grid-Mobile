import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

/// Extracted from RoomService._calculateDistance (private method).
/// We replicate it here for testing. When refactored to a utility, update import.
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371000; // Earth radius in meters
  final dLat = (lat2 - lat1) * (3.14159265359 / 180);
  final dLon = (lon2 - lon1) * (3.14159265359 / 180);

  final lat1Rad = lat1 * (3.14159265359 / 180);
  final lat2Rad = lat2 * (3.14159265359 / 180);

  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return R * c;
}

void main() {
  group('Haversine distance calculation', () {
    test('same point returns 0', () {
      expect(calculateDistance(40.7128, -74.0060, 40.7128, -74.0060), 0.0);
    });

    test('New York to Los Angeles (~3944 km)', () {
      final distance = calculateDistance(40.7128, -74.0060, 34.0522, -118.2437);
      // Allow 2% error margin
      expect(distance, closeTo(3944000, 80000));
    });

    test('London to Paris (~344 km)', () {
      final distance = calculateDistance(51.5074, -0.1278, 48.8566, 2.3522);
      expect(distance, closeTo(344000, 7000));
    });

    test('short distance — 100 meters apart', () {
      // Roughly 100m north at latitude 40
      final distance = calculateDistance(40.0, -74.0, 40.0009, -74.0);
      expect(distance, closeTo(100, 10));
    });

    test('equator to north pole (~10,000 km)', () {
      final distance = calculateDistance(0, 0, 90, 0);
      expect(distance, closeTo(10018000, 50000));
    });

    test('antipodal points (~20,000 km)', () {
      final distance = calculateDistance(0, 0, 0, 180);
      expect(distance, closeTo(20036000, 50000));
    });

    test('negative coordinates (Southern hemisphere)', () {
      // Sydney to Auckland (~2156 km)
      final distance = calculateDistance(-33.8688, 151.2093, -36.8485, 174.7633);
      expect(distance, closeTo(2156000, 50000));
    });

    test('very small distance (< 10m threshold used in app)', () {
      // ~5 meters apart
      final distance = calculateDistance(40.7128, -74.0060, 40.71284, -74.0060);
      expect(distance, lessThan(10));
    });
  });
}
