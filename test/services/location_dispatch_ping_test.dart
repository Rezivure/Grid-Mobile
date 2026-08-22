import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/services/location/location_dispatch.dart';
import 'package:grid_frontend/services/location/location_update.dart';
import 'package:grid_frontend/services/sharing_state_notifier.dart';

LocationUpdate _fix({double lat = 40.0, double lng = -74.0}) => LocationUpdate(
      latitude: lat,
      longitude: lng,
      accuracy: 10,
      speed: 0,
      heading: 0,
      altitude: 0,
      timestamp: DateTime.now(),
      isMoving: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationDispatch manual ping (#153)', () {
    late SharingStateNotifier sharing;
    late LocationDispatch dispatch;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      sharing = SharingStateNotifier();
      dispatch = LocationDispatch(sharing);
    });

    test('forceNextPost overrides the throttle for a stationary re-ping', () {
      // First fix always posts and records position/time.
      expect(dispatch.shouldPost(_fix()), isTrue);
      // Immediate identical fix (no movement, no time) would normally be
      // throttled away — this is exactly the frozen-ping case.
      expect(dispatch.shouldPost(_fix()), isFalse);

      // Arming a ping forces the next otherwise-throttled fix through.
      dispatch.forceNextPost();
      expect(dispatch.shouldPost(_fix()), isTrue);
    });

    test('the override is one-shot and drains after a single post', () {
      expect(dispatch.shouldPost(_fix()), isTrue);
      dispatch.forceNextPost();
      expect(dispatch.shouldPost(_fix()), isTrue);
      // Next stationary fix is throttled again — the flag did not stick.
      expect(dispatch.shouldPost(_fix()), isFalse);
    });

    test('a ping never leaks while sharing is paused/incognito', () {
      expect(dispatch.shouldPost(_fix()), isTrue);
      sharing.setPausedAtHome(true);
      dispatch.forceNextPost();
      // Pause wins over the force flag — privacy is preserved.
      expect(dispatch.shouldPost(_fix()), isFalse);
    });

    test('a ping suppressed by pause does not linger into the next unpaused fix',
        () {
      expect(dispatch.shouldPost(_fix()), isTrue);
      sharing.setPausedAtHome(true);
      dispatch.forceNextPost();
      expect(dispatch.shouldPost(_fix()), isFalse); // dropped while paused
      sharing.setPausedAtHome(false);
      // The force flag was consumed while paused, so a normal stationary
      // fix is throttled as usual — no delayed surprise broadcast.
      expect(dispatch.shouldPost(_fix()), isFalse);
    });
  });
}
