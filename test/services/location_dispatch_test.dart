import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/services/location/location_dispatch.dart';
import 'package:grid_frontend/services/location/location_update.dart';
import 'package:grid_frontend/services/sharing_state_notifier.dart';

/// Builds a plausible fix. Only lat/lng vary across these tests.
LocationUpdate _fix(double lat, double lng) => LocationUpdate(
      latitude: lat,
      longitude: lng,
      accuracy: 10.0,
      speed: 0.0,
      heading: 0.0,
      altitude: 0.0,
      timestamp: DateTime.now(),
      isMoving: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationDispatch.shouldPost coordinate guard', () {
    late LocationDispatch dispatch;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dispatch = LocationDispatch(SharingStateNotifier());
      await dispatch.start();
    });

    test('posts the first valid fix', () {
      expect(dispatch.shouldPost(_fix(40.7128, -74.0060)), isTrue);
    });

    test('drops a NaN fix and never records it as the last position', () {
      // First real fix establishes bookkeeping.
      expect(dispatch.shouldPost(_fix(40.7128, -74.0060)), isTrue);

      // A NaN fix must be rejected...
      expect(dispatch.shouldPost(_fix(double.nan, double.nan)), isFalse);

      // ...and must NOT have poisoned the bookkeeping: a nearby real fix a
      // few meters away should still be throttled on distance (not forced
      // through by a NaN haversine). Same coords ⇒ 0m ⇒ under threshold.
      expect(dispatch.shouldPost(_fix(40.7128, -74.0060)), isFalse);
    });

    test('drops an Infinity fix', () {
      expect(dispatch.shouldPost(_fix(double.infinity, 0.0)), isFalse);
    });

    test('drops out-of-range coordinates', () {
      expect(dispatch.shouldPost(_fix(91.0, 0.0)), isFalse);
      expect(dispatch.shouldPost(_fix(0.0, 181.0)), isFalse);
    });

    test('an invalid fix does not consume the first-fix slot', () {
      // An invalid fix arriving first must not count as "the first fix";
      // the next genuine fix should still post as the session opener.
      expect(dispatch.shouldPost(_fix(double.nan, 0.0)), isFalse);
      expect(dispatch.shouldPost(_fix(48.8566, 2.3522)), isTrue);
    });
  });
}
