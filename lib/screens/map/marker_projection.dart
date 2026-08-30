import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show TargetPlatform;

/// Helpers for normalising maplibre-native's projected screen coordinates
/// into the logical-pixel space that Flutter's widget layer expects.
///
/// maplibre-native's Android `Projection.toScreenLocation` returns points in
/// PHYSICAL device pixels, whereas Flutter's `Positioned`/`Offset` work in
/// LOGICAL pixels. On high-DPR devices (e.g. an S24 Ultra at ~3x) this makes
/// overlay markers drift across the screen at roughly devicePixelRatio× the
/// map's pan speed and only line up with the map at the origin (0,0).
/// iOS already returns logical points, so no correction is applied there.
/// See Grid-Mobile issues #303 and #301.

/// The divisor to apply to raw maplibre screen coordinates for [platform].
///
/// Android reports physical pixels, so divide by [devicePixelRatio]; every
/// other platform already reports logical pixels, so divide by 1. A
/// non-positive [devicePixelRatio] is treated as 1 to avoid corrupting the
/// projection when the ratio is unavailable.
double markerProjectionDivisor(
  TargetPlatform platform,
  double devicePixelRatio,
) {
  if (platform == TargetPlatform.android && devicePixelRatio > 0) {
    return devicePixelRatio;
  }
  return 1.0;
}

/// Convert a raw projected screen point into logical pixels using [divisor].
///
/// A non-positive [divisor] is treated as 1 (identity) so a bad ratio can
/// never blow up marker placement.
Offset logicalMarkerOffset(double rawX, double rawY, double divisor) {
  final d = divisor <= 0 ? 1.0 : divisor;
  return Offset(rawX / d, rawY / d);
}
