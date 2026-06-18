import 'dart:async';
import 'dart:math' as math;

import 'package:libre_location/libre_location.dart' as libre;
import 'package:shared_preferences/shared_preferences.dart';

import '../sharing_state_notifier.dart';

/// Registers a single libre_location geofence around the user's saved
/// home, listens for ENTER/EXIT, and flips [SharingStateNotifier] so the
/// throttle in [LocationDispatch] stops posting while the user is home.
///
/// Reads:
///   - `home_location` pref → `"<lat>,<lng>"`
///   - `home_radius` pref   → double (meters)
///   - `auto_pause_at_home_enabled` pref → bool master switch
///
/// All three are owned by `SettingsPage` today; this service is the only
/// thing that consumes them outside of the map's visual circle.
///
/// `start()` is idempotent. Call `syncFromPrefs()` whenever the user
/// changes home location / radius / the master toggle.
class HomeGeofenceService {
  HomeGeofenceService(this._sharingState);

  final SharingStateNotifier _sharingState;

  // Platform geofences below this radius produce false triggers on
  // most phones (the OS's own location accuracy floor is ~50–100m).
  // The UI can let the user pick smaller values for the visual circle,
  // but for the actual platform-monitored region we clamp up.
  static const double _minPlatformRadiusM = 50;

  static const String _geofenceId = 'grid_home';

  StreamSubscription<libre.GeofenceEvent>? _sub;
  bool _started = false;
  bool _registered = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = libre.LibreLocation.geofenceStream.listen(_onEvent);
    await syncFromPrefs();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (_registered) {
      try {
        await libre.LibreLocation.removeGeofence(_geofenceId);
      } catch (_) {}
      _registered = false;
    }
    _started = false;
  }

  /// Re-reads the home prefs and registers (or removes) the platform
  /// geofence. Safe to call repeatedly — `addGeofence` is idempotent on
  /// the same id and we explicitly remove first to refresh radius
  /// changes cleanly.
  Future<void> syncFromPrefs() async {
    // When sharing is fully off, monitor nothing — a live geofence keeps the
    // OS location indicator lit even with tracking stopped.
    if (_sharingState.userIncognito) {
      await _unregister();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('auto_pause_at_home_enabled') ?? false;
    final raw = prefs.getString('home_location');
    final radius = prefs.getDouble('home_radius') ?? 25;

    if (!enabled || raw == null || raw.isEmpty) {
      await _unregister();
      return;
    }

    final parts = raw.split(',');
    if (parts.length != 2) {
      await _unregister();
      return;
    }
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) {
      await _unregister();
      return;
    }

    // Clamp to platform minimum. Visual circle in the picker can still
    // show 10m; the monitored region uses the floor.
    final effective = math.max(radius, _minPlatformRadiusM);

    try {
      // Remove any existing registration first so radius/lat/lng
      // changes take effect rather than silently no-op'ing.
      await libre.LibreLocation.removeGeofence(_geofenceId);
    } catch (_) {}

    try {
      await libre.LibreLocation.addGeofence(
        libre.Geofence(
          id: _geofenceId,
          latitude: lat,
          longitude: lng,
          radiusMeters: effective,
          triggers: const {
            libre.GeofenceTransition.enter,
            libre.GeofenceTransition.exit,
          },
        ),
      );
      _registered = true;
    } catch (_) {
      // Plugin may not be tracking yet (no permission, or location
      // service disabled). The pref is set; we'll be re-driven from
      // settings the next time the user touches the toggle.
      _registered = false;
    }
  }

  Future<void> _unregister() async {
    if (!_registered) return;
    try {
      await libre.LibreLocation.removeGeofence(_geofenceId);
    } catch (_) {}
    _registered = false;
  }

  void _onEvent(libre.GeofenceEvent event) {
    if (event.geofence.id != _geofenceId) return;
    switch (event.transition) {
      case libre.GeofenceTransition.enter:
        // Pause sharing while the user is at home. LocationDispatch
        // reads isPaused on the next fix and stops posting; an "at
        // home" final post will already have been sent on the STILL
        // transition that triggered this enter.
        _sharingState.setPausedAtHome(true);
        break;
      case libre.GeofenceTransition.exit:
        _sharingState.setPausedAtHome(false);
        break;
      case libre.GeofenceTransition.dwell:
        // Not registered — no-op.
        break;
    }
  }
}
