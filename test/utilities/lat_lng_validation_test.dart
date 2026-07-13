import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/utilities/lat_lng_validation.dart';

void main() {
  group('isFiniteLatLng', () {
    test('accepts a normal in-range fix', () {
      expect(isFiniteLatLng(40.7128, -74.0060), isTrue);
    });

    test('rejects NaN / Infinity', () {
      expect(isFiniteLatLng(double.nan, 0.0), isFalse);
      expect(isFiniteLatLng(0.0, double.infinity), isFalse);
    });

    test('rejects out-of-range coordinates', () {
      expect(isFiniteLatLng(91.0, 0.0), isFalse);
      expect(isFiniteLatLng(0.0, 181.0), isFalse);
    });
  });

  group('isNoFixSentinel', () {
    test('flags exact Null Island', () {
      expect(isNoFixSentinel(0.0, 0.0), isTrue);
    });

    test('flags a zeroed latitude axis (Indian Ocean pin signature)', () {
      // Real Bengaluru longitude, latitude dropped to the no-fix sentinel.
      expect(isNoFixSentinel(0.0, 77.5946), isTrue);
    });

    test('flags a zeroed longitude axis', () {
      expect(isNoFixSentinel(51.5074, 0.0), isTrue);
    });

    test('does not flag a genuine sub-degree fix', () {
      expect(isNoFixSentinel(0.0001, 0.0001), isFalse);
      expect(isNoFixSentinel(-33.8688, 151.2093), isFalse);
      expect(isNoFixSentinel(40.7128, -74.0060), isFalse);
    });
  });
}
