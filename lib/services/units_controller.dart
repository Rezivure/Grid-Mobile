import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unit used to show contacts' speed. Speeds are always sent and stored in
/// meters per second; this only changes how they're displayed.
enum SpeedUnit {
  mph('mph'),
  kmh('km/h'),
  mps('m/s');

  const SpeedUnit(this.label);
  final String label;

  static SpeedUnit fromPrefValue(String? raw) => SpeedUnit.values.firstWhere(
        (u) => u.name == raw,
        orElse: () => SpeedUnit.mph,
      );
}

/// Below this a contact counts as not moving, so no speed is shown.
const double minDisplaySpeedMps = 1.4;

/// Speed as "12 mph" / "19 km/h" / "5.4 m/s". Null when no useful motion or
/// speed isn't known.
String? formatSpeed(double? speedMps, SpeedUnit unit) {
  if (speedMps == null || speedMps < minDisplaySpeedMps) return null;
  return switch (unit) {
    SpeedUnit.mph => '${(speedMps * 2.236936).round()} mph',
    SpeedUnit.kmh => '${(speedMps * 3.6).round()} km/h',
    // Walking speeds are only a few m/s, so keep one decimal.
    SpeedUnit.mps => '${speedMps.toStringAsFixed(1)} m/s',
  };
}

/// User-selectable speed unit. Defaults to mph, which is what Grid showed
/// before the setting existed; the user can change it from Settings.
class UnitsController extends ChangeNotifier {
  UnitsController._();
  static final UnitsController instance = UnitsController._();

  static const _prefsKey = 'speed_unit';

  SpeedUnit _speedUnit = SpeedUnit.mph;
  SpeedUnit get speedUnit => _speedUnit;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _speedUnit = SpeedUnit.fromPrefValue(prefs.getString(_prefsKey));
    notifyListeners();
  }

  Future<void> setSpeedUnit(SpeedUnit unit) async {
    if (unit == _speedUnit) return;
    _speedUnit = unit;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, unit.name);
  }
}
