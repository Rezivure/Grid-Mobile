// lib/services/sharing_state_notifier.dart
//
// Single source of truth for the user's "sharing paused" state.
//
// Today the value is persisted under the SharedPreferences key
// `incognito_mode` (true when sharing is OFF / incognito ON). The
// settings page wrote to that key directly, which meant other widgets
// (notably the map's "SHARING WITH N" pill) had no way to react when
// the user toggled sharing off.
//
// This notifier loads the value on construction and rebroadcasts any
// changes so anything watching it (e.g. the pill) re-renders.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharingStateNotifier extends ChangeNotifier {
  static const String _prefsKey = 'incognito_mode';

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  SharingStateNotifier() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_prefsKey) ?? false;
    if (value != _isPaused) {
      _isPaused = value;
      notifyListeners();
    }
  }

  /// Persists [value] to SharedPreferences and notifies listeners.
  /// `true`  = sharing OFF / incognito ON (paused)
  /// `false` = sharing ON (normal)
  Future<void> setPaused(bool value) async {
    if (_isPaused == value) {
      // Still write through so on-disk state matches, but don't spam
      // listeners with no-op rebuilds.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
      return;
    }
    _isPaused = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
    notifyListeners();
  }
}
