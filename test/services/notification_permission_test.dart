import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/services/location/libre_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const asked = 'notification_permission_asked';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a request that fails is retried on the next start', () async {
    var calls = 0;
    await LibreLocationService.requestNotificationPermissionOnce(
      isAndroid: true,
      request: () async {
        calls++;
        throw PlatformException(code: 'NO_ACTIVITY');
      },
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(asked), isNull);

    await LibreLocationService.requestNotificationPermissionOnce(
      isAndroid: true,
      request: () async {
        calls++;
        return true;
      },
    );
    expect(calls, 2);
    expect(prefs.getBool(asked), isTrue);
  });

  test('a denial counts as asked, there is no second prompt', () async {
    var calls = 0;
    Future<bool> deny() async {
      calls++;
      return false;
    }

    await LibreLocationService.requestNotificationPermissionOnce(
        isAndroid: true, request: deny);
    await LibreLocationService.requestNotificationPermissionOnce(
        isAndroid: true, request: deny);
    expect(calls, 1);
  });

  test('nothing is asked outside Android', () async {
    var calls = 0;
    await LibreLocationService.requestNotificationPermissionOnce(
      isAndroid: false,
      request: () async {
        calls++;
        return true;
      },
    );
    expect(calls, 0);
    expect((await SharedPreferences.getInstance()).getBool(asked), isNull);
  });
}
