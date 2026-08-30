/// Returns true only when both coordinates are finite and in valid range.
/// Used as the chokepoint guard before any value is handed to MapLibre's
/// native `LatLng` constructor, which throws an uncaught C++ exception
/// (SIGABRT) on NaN/Inf/out-of-range input.
bool isFiniteLatLng(num lat, num lng) {
  if (lat is double && (lat.isNaN || lat.isInfinite)) return false;
  if (lng is double && (lng.isNaN || lng.isInfinite)) return false;
  return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

/// True for exact Null Island — `(0.0, 0.0)` on both axes.
///
/// A zero-initialised location struct that never received a fix serialises as
/// exactly `(0, 0)`, so this is the conventional "unset coordinate" check. It
/// is defence in depth: nothing in Grid is known to emit it today, but a
/// no-fix reading that slipped through would render a contact in the Gulf of
/// Guinea and be re-broadcast to peers.
///
/// **Both** axes must be zero. An earlier revision of this guard rejected a
/// zero on *either* axis, which would also discard genuine fixes on the
/// equator or the prime meridian — real places, including populated parts of
/// Ecuador, Kenya, Indonesia, Ghana and the UK. That trade was not worth
/// making for a sentinel that is only ever emitted with both axes zeroed.
///
/// Note this deliberately does not chase pins that *drift as the map pans* —
/// that symptom is a screen-space projection error, not a bad coordinate.
/// See PR #316.
bool isNoFixSentinel(num lat, num lng) => lat == 0.0 && lng == 0.0;
