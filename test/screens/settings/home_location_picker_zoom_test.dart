import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/screens/settings/home_location_picker_screen.dart';

/// On-screen diameter of a circle of [radiusMeters] at [zoom] and [latitude].
double diameterPx(double radiusMeters, double latitude, double zoom) =>
    2 * radiusMeters /
    (78271.516 * math.cos(latitude * math.pi / 180) / math.pow(2, zoom));

void main() {
  test('the circle fills about 55 % of the screen at any radius', () {
    for (final r in [50.0, 150.0, 300.0]) {
      final z = homePickerZoomForRadius(
          radiusMeters: r, latitude: 52.13, screenWidth: 411);
      expect(diameterPx(r, 52.13, z), closeTo(0.55 * 411, 0.5), reason: '$r m');
    }
  });

  test('a larger radius zooms out', () {
    double z(double r) => homePickerZoomForRadius(
        radiusMeters: r, latitude: 52.13, screenWidth: 411);
    expect(z(300), lessThan(z(150)));
    expect(z(150), lessThan(z(50)));
  });

  test('stays within the zoom limits', () {
    expect(
        homePickerZoomForRadius(
            radiusMeters: 0.5, latitude: 0, screenWidth: 411),
        19.0);
    expect(
        homePickerZoomForRadius(
            radiusMeters: 300, latitude: 52.13, screenWidth: 0),
        16);
  });
}
