import 'dart:math' as math;

/// Geometry helpers for the map's floating compass rose.
///
/// MapLibre reports the camera bearing in degrees measured clockwise from
/// true north (rotating the map clockwise increases the bearing). The compass
/// rose is a fixed graphic whose red arrow must keep pointing at true north on
/// screen, so it has to counter-rotate against the camera bearing.
///
/// [Transform.rotate] treats a positive angle as a clockwise turn, therefore
/// the rose must be rotated by the negated bearing. Rotating it by `+bearing`
/// (the previous behaviour) spun the arrow the wrong way — see issue #304.
double compassRoseAngleRadians(double bearingDegrees) {
  return -bearingDegrees * (math.pi / 180.0);
}
