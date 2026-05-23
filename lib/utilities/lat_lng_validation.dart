/// Returns true only when both coordinates are finite and in valid range.
/// Used as the chokepoint guard before any value is handed to MapLibre's
/// native `LatLng` constructor, which throws an uncaught C++ exception
/// (SIGABRT) on NaN/Inf/out-of-range input.
bool isFiniteLatLng(num lat, num lng) {
  if (lat is double && (lat.isNaN || lat.isInfinite)) return false;
  if (lng is double && (lng.isNaN || lng.isInfinite)) return false;
  return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}
