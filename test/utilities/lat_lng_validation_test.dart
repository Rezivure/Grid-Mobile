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

    test('does NOT flag a real fix on the equator', () {
      // Quito sits within a hair of 0 latitude; Kenya, Indonesia and Ecuador
      // are all populated equatorial places. A zeroed longitude alone is not
      // evidence of a no-fix reading.
      expect(isNoFixSentinel(0.0, 77.5946), isFalse);
      expect(isNoFixSentinel(0.0, -78.4678), isFalse);
    });

    test('does NOT flag a real fix on the prime meridian', () {
      // Greenwich, and everything else on 0 longitude from Ghana to the UK.
      expect(isNoFixSentinel(51.5074, 0.0), isFalse);
      expect(isNoFixSentinel(5.6037, 0.0), isFalse);
    });

    test('does not flag ordinary fixes', () {
      expect(isNoFixSentinel(0.0001, 0.0001), isFalse);
      expect(isNoFixSentinel(-33.8688, 151.2093), isFalse);
      expect(isNoFixSentinel(40.7128, -74.0060), isFalse);
    });
  });
}
