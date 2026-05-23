import 'package:flutter/foundation.dart';

/// In-memory snapshot of a contact's last-known device-side context
/// (speed/heading/accuracy + battery). Lives separately from the
/// encrypted lat/lng row in `LocationRepository` because:
///
///   1. The UI only ever wants the *latest* value — we don't need to
///      query historical battery readings.
///   2. Avoiding a database migration on every additive field keeps
///      this surface flexible (gridv 3 can add altitude/accelerometer
///      whatever without touching SQLite).
///
/// `ChangeNotifier` so widgets can `Provider.of` and watch a single
/// user's status without polling. Notifies on every update; callers
/// that only care about a single user should select with
/// `context.select<UserDeviceStatusCache, DeviceStatus?>(...)` to avoid
/// unnecessary rebuilds.
class UserDeviceStatusCache extends ChangeNotifier {
  static final UserDeviceStatusCache instance =
      UserDeviceStatusCache._internal();
  UserDeviceStatusCache._internal();

  final Map<String, DeviceStatus> _byUser = {};

  DeviceStatus? statusFor(String userId) => _byUser[userId];

  void update(String userId, DeviceStatus status) {
    _byUser[userId] = status;
    notifyListeners();
  }

  void clear() {
    _byUser.clear();
    notifyListeners();
  }
}

class DeviceStatus {
  const DeviceStatus({
    this.speed,
    this.heading,
    this.accuracy,
    this.batteryLevel,
    this.isCharging,
    required this.updatedAt,
  });

  /// Speed in meters per second. Null when not known.
  final double? speed;

  /// Bearing in degrees [0, 360). Null when not known.
  final double? heading;

  /// Accuracy radius in meters. Null when not known.
  final double? accuracy;

  /// Battery level 0.0–1.0. Null when the sender's plugin couldn't
  /// read it or when the sender is on an old (pre-gridv2) build.
  final double? batteryLevel;

  /// True if the sender's device was plugged in at the time of the fix.
  /// Null when unknown.
  final bool? isCharging;

  /// Server-decided time at which we received this status. Used by the
  /// UI to decide whether to show the value or grey it out.
  final DateTime updatedAt;
}
