// lib/services/sharing_state_notifier.dart
//
// Single source of truth for the user's "sharing paused" state.
//
// Two independent inputs combine into the effective paused state:
//   * `userIncognito` — the deliberate user toggle from settings.
//     Persisted under the legacy `incognito_mode` pref key.
//   * `pausedAtHome` — transient, set by HomeGeofenceService on
//     ENTER/EXIT. NOT persisted; geofence re-fires on app boot.
//
// `isPaused = userIncognito || pausedAtHome` — what LocationDispatch
// and the map pill consume. Settings UI should render `userIncognito`
// so a geofence transition doesn't visually flip the toggle.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharingStateNotifier extends ChangeNotifier {
  static const String _userIncognitoKey = 'incognito_mode';

  bool _userIncognito = false;
  bool _pausedAtHome = false;

  bool get userIncognito => _userIncognito;
  bool get pausedAtHome => _pausedAtHome;
  bool get isPaused => _userIncognito || _pausedAtHome;

  SharingStateNotifier() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_userIncognitoKey) ?? false;
    if (value != _userIncognito) {
      _userIncognito = value;
      notifyListeners();
    }
  }

  /// Persists the user's deliberate incognito toggle.
  Future<void> setUserIncognito(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_userIncognitoKey, value);
    if (_userIncognito == value) return;
    _userIncognito = value;
    notifyListeners();
  }

  /// Ephemeral geofence-driven pause; not persisted.
  void setPausedAtHome(bool value) {
    if (_pausedAtHome == value) return;
    _pausedAtHome = value;
    notifyListeners();
  }
}
