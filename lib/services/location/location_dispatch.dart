import 'dart:async';
import 'dart:math' as math;

import 'package:libre_location/libre_location.dart' as libre;
import 'package:shared_preferences/shared_preferences.dart';

import '../sharing_state_notifier.dart';
import 'location_update.dart';

/// User-facing "Sharing mode" — maps to a `libre_location` preset plus a
/// throttling profile inside [LocationDispatch].
enum SharingMode { light, balanced, live }

extension SharingModePref on SharingMode {
  String get prefValue => switch (this) {
        SharingMode.light => 'light',
        SharingMode.balanced => 'balanced',
        SharingMode.live => 'live',
      };

  libre.TrackingPreset get preset => switch (this) {
        SharingMode.light => libre.TrackingPreset.low,
        SharingMode.balanced => libre.TrackingPreset.balanced,
        SharingMode.live => libre.TrackingPreset.high,
      };

  static SharingMode fromPrefValue(String? raw) => switch (raw) {
        'light' => SharingMode.light,
        'live' => SharingMode.live,
        _ => SharingMode.balanced,
      };
}

/// Coarse activity bucket derived from `libre_location.onActivityChange`.
enum LocationActivity { still, walking, inVehicle, unknown }

/// Decides which raw GPS fixes become Matrix posts.
///
/// Sits between `LocationManager.locationStream` and
/// `RoomService.updateRooms`. Maintains a small state machine driven by
/// the plugin's motion + activity streams; throttles posting per state +
/// per current [SharingMode]; respects [SharingStateNotifier.isPaused]
/// (the single chokepoint that closes both the mid-session-incognito
/// bug and the auto-pause-at-home flow).
///
/// `start()` is idempotent — safe to call once at app boot.
class LocationDispatch {
  LocationDispatch(this._sharingState);

  final SharingStateNotifier _sharingState;

  SharingMode _mode = SharingMode.balanced;
  LocationActivity _activity = LocationActivity.unknown;
  DateTime? _lastPostAt;
  LocationUpdate? _lastPostedLocation;

  /// True after a STILL transition until the next post drains it. Forces
  /// one "final" post when the user stops moving so contacts see the
  /// resting position immediately.
  bool _justEnteredStill = false;

  // Cruise-mode detection (sustained high-speed driving). Lets the
  // throttle relax once we're confident the user is on the highway —
  // posting every 250m/30s on I-95 for 2 hours is the case that wrecks
  // the battery if we don't back off.
  DateTime? _highSpeedSince;
  bool _isCruising = false;

  StreamSubscription<libre.Position>? _motionSub;
  StreamSubscription<libre.ActivityEvent>? _activitySub;

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Hydrate the user-chosen mode without blocking the start path.
    final prefs = await SharedPreferences.getInstance();
    _mode = SharingModePref.fromPrefValue(prefs.getString('sharing_mode'));

    _motionSub = libre.LibreLocation.onMotionChange.listen((p) {
      if (!p.isMoving) {
        _justEnteredStill = true;
      }
    });
    _activitySub = libre.LibreLocation.onActivityChange.listen((e) {
      _activity = _mapActivity(e.activity);
    });
  }

  Future<void> stop() async {
    await _motionSub?.cancel();
    _motionSub = null;
    await _activitySub?.cancel();
    _activitySub = null;
    _started = false;
  }

  SharingMode get mode => _mode;

  /// Switches the user-facing mode. Persists the choice, swaps the
  /// underlying `libre_location` preset, and rewires the throttle on
  /// the next fix.
  Future<void> setMode(SharingMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sharing_mode', mode.prefValue);
    try {
      await libre.LibreLocation.setPreset(mode.preset);
    } catch (_) {
      // Plugin may not be tracking yet (e.g. user hasn't granted
      // location permission). The chosen mode is persisted; when
      // tracking starts the chosen preset will be applied via
      // libre's normal start path.
    }
  }

  /// Returns true if [fix] should be posted to Matrix. Records the post
  /// for distance/interval bookkeeping when true.
  bool shouldPost(LocationUpdate fix) {
    if (_sharingState.isPaused) return false;

    final now = DateTime.now();
    final last = _lastPostAt;
    final prev = _lastPostedLocation;

    // First fix in this session → always send.
    if (last == null || prev == null) {
      _record(fix, now);
      return true;
    }

    // Final-post-on-stop: one decisive update when the user transitions
    // to STILL, so contacts see "arrived" promptly. Then suppression
    // kicks in until motion resumes.
    if (_justEnteredStill) {
      _justEnteredStill = false;
      _record(fix, now);
      return true;
    }

    _updateCruiseState(fix, now);

    final elapsed = now.difference(last);
    final distance = _haversineMeters(
      prev.latitude,
      prev.longitude,
      fix.latitude,
      fix.longitude,
    );
    final t = _thresholdsFor(_activity, _mode, cruising: _isCruising);

    if (distance >= t.distanceM || elapsed >= t.interval) {
      _record(fix, now);
      return true;
    }

    // Stationary heartbeat — even when locked still, post once every
    // heartbeat window so the "Bing - 2m ago" timestamp doesn't slowly
    // creep up to "an hour ago" on idle phones.
    if (_activity == LocationActivity.still && elapsed >= t.heartbeat) {
      _record(fix, now);
      return true;
    }

    return false;
  }

  void _record(LocationUpdate fix, DateTime at) {
    _lastPostedLocation = fix;
    _lastPostAt = at;
  }

  void _updateCruiseState(LocationUpdate fix, DateTime now) {
    if (_activity != LocationActivity.inVehicle) {
      _isCruising = false;
      _highSpeedSince = null;
      return;
    }
    // 13.9 m/s = 50 km/h ≈ 31 mph. Sustained for 2 min ⇒ highway-y.
    if (fix.speed >= 13.9) {
      _highSpeedSince ??= now;
      if (now.difference(_highSpeedSince!).inMinutes >= 2) {
        _isCruising = true;
      }
    } else {
      _highSpeedSince = null;
      _isCruising = false;
    }
  }

  LocationActivity _mapActivity(String? activity) {
    switch (activity) {
      case 'still':
        return LocationActivity.still;
      case 'walking':
      case 'on_foot':
      case 'running':
      case 'on_bicycle':
        return LocationActivity.walking;
      case 'in_vehicle':
        return LocationActivity.inVehicle;
      default:
        return LocationActivity.unknown;
    }
  }

  _Thresholds _thresholdsFor(
    LocationActivity activity,
    SharingMode mode, {
    required bool cruising,
  }) {
    // Light mode: state-transition pings + 15-min heartbeat, regardless
    // of activity. This is the "I just want my friends to know roughly
    // where I am" tier.
    if (mode == SharingMode.light) {
      return const _Thresholds(
        distanceM: 1000,
        interval: Duration(minutes: 5),
        heartbeat: Duration(minutes: 15),
      );
    }

    // Cruise overrides the in-vehicle defaults for sustained highway
    // driving. Same in Balanced and Live — the user already chose a
    // tier; cruise just relaxes the worst case (long monotonous drives).
    if (cruising) {
      return const _Thresholds(
        distanceM: 750,
        interval: Duration(seconds: 90),
        heartbeat: Duration(minutes: 5),
      );
    }

    switch (activity) {
      case LocationActivity.inVehicle:
        return mode == SharingMode.live
            ? const _Thresholds(
                distanceM: 100,
                interval: Duration(seconds: 15),
                heartbeat: Duration(minutes: 5),
              )
            : const _Thresholds(
                distanceM: 250,
                interval: Duration(seconds: 30),
                heartbeat: Duration(minutes: 5),
              );
      case LocationActivity.walking:
        return mode == SharingMode.live
            ? const _Thresholds(
                distanceM: 25,
                interval: Duration(seconds: 30),
                heartbeat: Duration(minutes: 10),
              )
            : const _Thresholds(
                distanceM: 100,
                interval: Duration(seconds: 60),
                heartbeat: Duration(minutes: 10),
              );
      case LocationActivity.still:
        // Stationary heartbeat is mode-aware: Live keeps contacts fresh even
        // when not moving (the point of live sharing); Light sips battery.
        switch (mode) {
          case SharingMode.live:
            return const _Thresholds(
              distanceM: 999999,
              interval: Duration(minutes: 5),
              heartbeat: Duration(seconds: 45),
            );
          case SharingMode.balanced:
            return const _Thresholds(
              distanceM: 999999,
              interval: Duration(minutes: 10),
              heartbeat: Duration(minutes: 5),
            );
          case SharingMode.light:
            return const _Thresholds(
              distanceM: 999999, // effectively never on distance alone
              interval: Duration(minutes: 30),
              heartbeat: Duration(minutes: 15),
            );
        }
      case LocationActivity.unknown:
        // Before the activity classifier has weighed in. Be conservative —
        // every 60s or 100m. This is the bootup state.
        return const _Thresholds(
          distanceM: 100,
          interval: Duration(seconds: 60),
          heartbeat: Duration(minutes: 15),
        );
    }
  }

  // Haversine distance in meters between two lat/lng pairs.
  static double _haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthMeters = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthMeters * c;
  }
}

class _Thresholds {
  const _Thresholds({
    required this.distanceM,
    required this.interval,
    required this.heartbeat,
  });
  final double distanceM;
  final Duration interval;
  final Duration heartbeat;
}
