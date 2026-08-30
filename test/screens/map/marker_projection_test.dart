import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/screens/map/marker_projection.dart';

void main() {
  group('markerProjectionDivisor', () {
    test('Android divides by devicePixelRatio (physical -> logical pixels)', () {
      expect(markerProjectionDivisor(TargetPlatform.android, 3.0), 3.0);
      expect(markerProjectionDivisor(TargetPlatform.android, 2.625), 2.625);
    });

    test('iOS leaves coordinates untouched (already logical)', () {
      expect(markerProjectionDivisor(TargetPlatform.iOS, 3.0), 1.0);
    });

    test('non-Android platforms are identity regardless of ratio', () {
      expect(markerProjectionDivisor(TargetPlatform.macOS, 2.0), 1.0);
      expect(markerProjectionDivisor(TargetPlatform.linux, 4.0), 1.0);
    });

    test('a non-positive ratio falls back to identity on Android', () {
      expect(markerProjectionDivisor(TargetPlatform.android, 0.0), 1.0);
      expect(markerProjectionDivisor(TargetPlatform.android, -2.0), 1.0);
    });
  });

  group('logicalMarkerOffset', () {
    test('scales a physical-pixel point down to logical pixels', () {
      final o = logicalMarkerOffset(300, 600, 3.0);
      expect(o.dx, 100);
      expect(o.dy, 200);
    });

    test('divisor of 1 is identity (iOS / non-Android path)', () {
      final o = logicalMarkerOffset(123.5, 456.5, 1.0);
      expect(o.dx, 123.5);
      expect(o.dy, 456.5);
    });

    test('the origin projects to the origin at any divisor', () {
      // Matches the reported symptom: markers only lined up at (0,0) because
      // 0/dpr == 0. Correction must preserve that fixed point.
      expect(logicalMarkerOffset(0, 0, 3.0), logicalMarkerOffset(0, 0, 1.0));
    });

    test('non-positive divisor is treated as identity (never blows up)', () {
      final o = logicalMarkerOffset(300, 600, 0.0);
      expect(o.dx, 300);
      expect(o.dy, 600);
    });

    test('drift grows linearly with distance from origin before correction',
        () {
      // Pre-fix, a point 500 logical px from centre landed at 1500 physical
      // px on a 3x device (the "~4x speed" drift). Post-fix it returns to 500.
      const dpr = 3.0;
      final corrected = logicalMarkerOffset(500 * dpr, 500 * dpr, dpr);
      expect(corrected.dx, 500);
      expect(corrected.dy, 500);
    });
  });
}
