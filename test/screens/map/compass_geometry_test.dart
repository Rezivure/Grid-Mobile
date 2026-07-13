import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/screens/map/compass_geometry.dart';

void main() {
  group('compassRoseAngleRadians', () {
    test('no bearing leaves the rose upright', () {
      expect(compassRoseAngleRadians(0), 0.0);
    });

    test('counter-rotates against the camera bearing (issue #304)', () {
      // MapLibre bearing is clockwise-from-north; the rose must turn the
      // opposite way so its north arrow keeps pointing at true north.
      expect(compassRoseAngleRadians(90), closeTo(-math.pi / 2, 1e-12));
      expect(compassRoseAngleRadians(45), closeTo(-math.pi / 4, 1e-12));
    });

    test('is the negation of a naive same-direction rotation', () {
      for (final deg in [0.0, 30.0, 123.4, 180.0, 270.0, 359.9]) {
        final naive = deg * (math.pi / 180.0);
        expect(compassRoseAngleRadians(deg), closeTo(-naive, 1e-12));
      }
    });

    test('handles a full turn', () {
      expect(compassRoseAngleRadians(360), closeTo(-2 * math.pi, 1e-12));
    });
  });
}
