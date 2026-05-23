import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:grid_frontend/utilities/lat_lng_validation.dart';

/// Thin shim that exposes the small subset of `flutter_map`'s `MapController`
/// API that `map_tab.dart` actually uses, but delegates the work to a
/// `maplibre_gl` `MapLibreMapController`. Lets us swap the renderer with
/// minimal churn at the call sites.
///
/// Camera-position queries (`camera.center`, `camera.zoom`) are read from a
/// cached snapshot maintained by `onCameraIdle` — close enough for the existing
/// callers that only inspect them after gestures settle.
class MaplibreCameraFacade {
  ml.MapLibreMapController? _ml;
  CameraSnapshot _snapshot = const CameraSnapshot._empty();
  Size _mapSize = Size.zero;

  void attach(ml.MapLibreMapController controller) {
    _ml = controller;
    syncFromController();
  }

  void detach() {
    _ml = null;
  }

  /// Updates the camera snapshot from the live controller. Call this on
  /// `onCameraIdle` (and at attach).
  void syncFromController() {
    final pos = _ml?.cameraPosition;
    if (pos == null) return;
    final t = pos.target;
    _snapshot = CameraSnapshot._(
      center: LatLng(t.latitude, t.longitude),
      zoom: pos.zoom,
      bearing: pos.bearing,
      mapSize: _mapSize,
    );
  }

  void setMapSize(Size size) {
    _mapSize = size;
    _snapshot = _snapshot.copyWith(mapSize: size);
  }

  /// Snap to a position (no animation). Mirrors `MapController.move`.
  void move(LatLng center, double zoom) {
    if (!_foregrounded) return;
    if (!isFiniteLatLng(center.latitude, center.longitude)) {
      debugPrint('[Camera] Skipping move — invalid coords: ${center.latitude},${center.longitude}');
      return;
    }
    final z = _safeZoom(zoom);
    _ml?.moveCamera(ml.CameraUpdate.newCameraPosition(
      ml.CameraPosition(
        target: ml.LatLng(center.latitude, center.longitude),
        zoom: z,
      ),
    ));
  }

  /// Animate to a position + rotation. Mirrors `MapController.moveAndRotate`.
  /// `rotation` is in degrees; flutter_map called this with 0 to clear bearing.
  void moveAndRotate(LatLng center, double zoom, double rotation) {
    if (!_foregrounded) return;
    if (!isFiniteLatLng(center.latitude, center.longitude)) {
      debugPrint('[Camera] Skipping moveAndRotate — invalid coords: ${center.latitude},${center.longitude}');
      return;
    }
    final z = _safeZoom(zoom);
    final r = (rotation.isNaN || rotation.isInfinite) ? 0.0 : rotation;
    _ml?.animateCamera(ml.CameraUpdate.newCameraPosition(
      ml.CameraPosition(
        target: ml.LatLng(center.latitude, center.longitude),
        zoom: z,
        bearing: r,
      ),
    ));
  }

  // Backgrounded MLNMapView has a zero-size layer; MapLibre's bounds-clamp
  // math then produces NaN and the native LatLng constructor crashes the app.
  bool get _foregrounded =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  double _safeZoom(double zoom) {
    if (zoom.isNaN || zoom.isInfinite) return 2.0;
    return zoom.clamp(0.0, 22.0);
  }

  /// Mirrors `MapController.camera` from flutter_map.
  CameraSnapshot get camera => _snapshot;

  void dispose() {
    detach();
  }
}

/// Read-only camera state — what the old code accessed via
/// `_mapController.camera.{center,zoom,latLngToScreenPoint}`.
class CameraSnapshot {
  const CameraSnapshot._({
    required this.center,
    required this.zoom,
    required this.bearing,
    required this.mapSize,
  });

  const CameraSnapshot._empty()
      : center = null,
        zoom = 0,
        bearing = 0,
        mapSize = Size.zero;

  final LatLng? center;
  final double zoom;
  final double bearing;
  final Size mapSize;

  CameraSnapshot copyWith({
    LatLng? center,
    double? zoom,
    double? bearing,
    Size? mapSize,
  }) =>
      CameraSnapshot._(
        center: center ?? this.center,
        zoom: zoom ?? this.zoom,
        bearing: bearing ?? this.bearing,
        mapSize: mapSize ?? this.mapSize,
      );

  /// Synchronous best-effort Mercator projection. Used only for the
  /// icon-action-wheel placement in the old MapTab code path — close enough
  /// for that purpose. Use the controller's async `toScreenLocation` for
  /// anything that needs precision.
  Offset latLngToScreenPoint(LatLng point) {
    final c = center;
    if (c == null || mapSize == Size.zero) return Offset.zero;
    // Web Mercator projection at the current zoom & center.
    // maplibre-native uses a 512px tile size for vector tiles; the world is
    // 512 * 2^zoom pixels across. Using 256 here was half-scale and caused
    // overlay markers to drift behind the map at low zoom.
    final scale = math.pow(2, zoom).toDouble() * 512.0;
    Offset project(LatLng p) {
      final x = (p.longitude + 180) / 360;
      final sinLat = math.sin(p.latitude * math.pi / 180);
      final y = 0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi);
      return Offset(x * scale, y * scale);
    }
    final cp = project(c);
    final pp = project(point);
    return Offset(
      mapSize.width / 2 + (pp.dx - cp.dx),
      mapSize.height / 2 + (pp.dy - cp.dy),
    );
  }
}
