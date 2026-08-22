/// Returns true only when both coordinates are finite and in valid range.
/// Used as the chokepoint guard before any value is handed to MapLibre's
/// native `LatLng` constructor, which throws an uncaught C++ exception
/// (SIGABRT) on NaN/Inf/out-of-range input.
bool isFiniteLatLng(num lat, num lng) {
  if (lat is double && (lat.isNaN || lat.isInfinite)) return false;
  if (lng is double && (lng.isNaN || lng.isInfinite)) return false;
  return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

/// True when a coordinate looks like a platform "no-fix" sentinel rather than
/// a real GPS reading. Android's `getLastKnownLocation` (heartbeat / last-known
/// paths) can hand back a partially-populated fix where one axis is left at an
/// exact `0.0`. A genuine sub-degree GPS fix is never exactly `0.0` on an axis,
/// so an exact zero on *either* latitude or longitude means "unset". Left
/// through, a real longitude with a zeroed latitude (e.g. a user in India at
/// `0.0, 77.x`) renders the contact stranded in the Indian Ocean.
///
/// Deliberately an exact `== 0.0` test: it only ever matches the sentinel, so
/// there are no false positives to worry about (the equator / prime meridian
/// to six decimals is open ocean, not a place any user is reporting from).
bool isNoFixSentinel(num lat, num lng) => lat == 0.0 || lng == 0.0;
