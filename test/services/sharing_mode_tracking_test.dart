import 'package:flutter_test/flutter_test.dart';
import 'package:libre_location/libre_location.dart' as libre;
import 'package:grid_frontend/services/location/location_dispatch.dart';
import 'package:grid_frontend/services/location/location_service_config.dart';

/// Regression cover for #341: the user-facing Sharing mode must reach the
/// tracker. It used to be derived in two places from two different prefs,
/// so the settings UI could show one mode while tracking ran another.
void main() {
  group('SharingMode mappings', () {
    test('each mode maps to a distinct tracking tier', () {
      expect(SharingMode.light.trackingMode, TrackingMode.batterySaver);
      expect(SharingMode.balanced.trackingMode, TrackingMode.normal);
      expect(SharingMode.live.trackingMode, TrackingMode.live);

      final tiers = SharingMode.values.map((m) => m.trackingMode).toSet();
      expect(tiers.length, SharingMode.values.length,
          reason: 'two sharing modes collapsing to one tier is the #341 bug');
    });

    test('each mode maps to a distinct plugin preset', () {
      expect(SharingMode.light.preset, libre.TrackingPreset.low);
      expect(SharingMode.balanced.preset, libre.TrackingPreset.balanced);
      expect(SharingMode.live.preset, libre.TrackingPreset.high);

      final presets = SharingMode.values.map((m) => m.preset).toSet();
      expect(presets.length, SharingMode.values.length);
    });

    test('preset and trackingMode agree on relative ordering', () {
      // Both mappings must rank the modes the same way; if one is edited
      // without the other, tracking and the plugin preset disagree.
      const order = [SharingMode.light, SharingMode.balanced, SharingMode.live];
      expect(order.map((m) => m.preset).toList(),
          [libre.TrackingPreset.low, libre.TrackingPreset.balanced, libre.TrackingPreset.high]);
      expect(order.map((m) => m.trackingMode).toList(),
          [TrackingMode.batterySaver, TrackingMode.normal, TrackingMode.live]);
    });
  });

  group('sharing_mode pref round-trip', () {
    test('every mode survives persist + restore', () {
      for (final mode in SharingMode.values) {
        expect(SharingModePref.fromPrefValue(mode.prefValue), mode,
            reason: '${mode.name} did not round-trip through its pref value');
      }
    });

    test('absent or unknown pref falls back to balanced', () {
      expect(SharingModePref.fromPrefValue(null), SharingMode.balanced);
      expect(SharingModePref.fromPrefValue('nonsense'), SharingMode.balanced);
    });
  });
}
