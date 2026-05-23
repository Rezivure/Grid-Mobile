import 'package:flutter/foundation.dart';

/// Lightweight one-way bus so the Settings page can tell `MapTab` to
/// reload its "home" pin overlay after the user picks/clears the saved
/// home location. The map's overlay is read from SharedPreferences at
/// init; without this pulse it would stay stale until next launch.
///
/// Mirrors the pattern in `map_camera_signals.dart`.
class HomeLocationSignals {
  HomeLocationSignals._();

  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static void bump() {
    changed.value = changed.value + 1;
  }
}
