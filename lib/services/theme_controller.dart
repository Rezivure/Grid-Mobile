import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-overridable app theme mode. Default is `ThemeMode.system` so the app
/// continues to follow OS brightness until the user explicitly picks Light or
/// Dark from Settings. Singleton ChangeNotifier so the MaterialApp at the root
/// can rebuild on change without restarting the app.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _mode = _decode(raw);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(m));
  }

  static String _encode(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode _decode(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
