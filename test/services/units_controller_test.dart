import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/services/units_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('formatSpeed', () {
    test('hides speed when not moving or unknown', () {
      for (final unit in SpeedUnit.values) {
        expect(formatSpeed(null, unit), isNull);
        expect(formatSpeed(0, unit), isNull);
        expect(formatSpeed(1.39, unit), isNull);
      }
    });

    test('mph matches the previous hardcoded output', () {
      expect(formatSpeed(1.4, SpeedUnit.mph), '3 mph');
      expect(formatSpeed(13.9, SpeedUnit.mph), '31 mph');
    });

    test('km/h (issue #361)', () {
      expect(formatSpeed(1.4, SpeedUnit.kmh), '5 km/h');
      expect(formatSpeed(13.9, SpeedUnit.kmh), '50 km/h');
    });

    test('m/s keeps one decimal for walking speeds (issue #361)', () {
      expect(formatSpeed(1.4, SpeedUnit.mps), '1.4 m/s');
      expect(formatSpeed(13.888, SpeedUnit.mps), '13.9 m/s');
    });
  });

  group('SpeedUnit.fromPrefValue', () {
    test('round-trips every unit', () {
      for (final unit in SpeedUnit.values) {
        expect(SpeedUnit.fromPrefValue(unit.name), unit);
      }
    });

    test('falls back to mph for missing or unknown values', () {
      expect(SpeedUnit.fromPrefValue(null), SpeedUnit.mph);
      expect(SpeedUnit.fromPrefValue('furlongs'), SpeedUnit.mph);
    });
  });

  group('UnitsController', () {
    tearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await UnitsController.instance.load();
    });

    test('defaults to mph', () async {
      SharedPreferences.setMockInitialValues({});
      await UnitsController.instance.load();
      expect(UnitsController.instance.speedUnit, SpeedUnit.mph);
    });

    test('loads the saved unit', () async {
      SharedPreferences.setMockInitialValues({'speed_unit': 'kmh'});
      await UnitsController.instance.load();
      expect(UnitsController.instance.speedUnit, SpeedUnit.kmh);
    });

    test('persists and notifies on change', () async {
      SharedPreferences.setMockInitialValues({});
      await UnitsController.instance.load();
      var notified = 0;
      void listener() => notified++;
      UnitsController.instance.addListener(listener);
      addTearDown(() => UnitsController.instance.removeListener(listener));

      await UnitsController.instance.setSpeedUnit(SpeedUnit.mps);

      expect(UnitsController.instance.speedUnit, SpeedUnit.mps);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('speed_unit'), 'mps');
    });
  });
}
