import 'package:flutter/services.dart';

/// Bridges Flutter to Android's `Activity.moveTaskToBack`.
///
/// Why this exists: MapTab is the root route. On Android, a system-back gesture
/// on the root route finishes the Activity, which tears down the Flutter engine
/// and — as a side effect — stops the `location` foreground service. Users
/// pressing back on the map screen expect the app to go to the background (like
/// pressing Home), not to be killed with location sharing silently stopped
/// (GH #302). Sending the task to the back keeps the foreground service alive.
///
/// iOS has no root back button, so this is a no-op there.
class AppLifecycleChannel {
  AppLifecycleChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// Name MUST match the channel registered in MainActivity.kt.
  static const String channelName = 'app.mygrid.grid/lifecycle';

  final MethodChannel _channel;

  /// Pure decision: should a root-route back gesture background the app instead
  /// of finishing the Activity? Only on Android, and only when the framework
  /// did not already pop a route (i.e. we're at the root).
  static bool shouldMoveToBackground({
    required bool didPop,
    required TargetPlatform platform,
  }) =>
      !didPop && platform == TargetPlatform.android;

  /// Ask Android to send the task to the background. Returns true if native
  /// handled it. Never throws — if the platform channel is unavailable (iOS,
  /// tests, or an old build without the native side) we fail closed to false so
  /// callers can fall back to default behaviour.
  Future<bool> moveTaskToBack() async {
    try {
      final handled = await _channel.invokeMethod<bool>('moveTaskToBack');
      return handled ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
