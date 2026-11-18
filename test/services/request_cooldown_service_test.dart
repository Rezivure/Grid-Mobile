import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/services/request_cooldown_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const user = '@contact:example.org';
  int ago(Duration d) => DateTime.now().subtract(d).millisecondsSinceEpoch;

  test('an unanswered request blocks for a day only while we show a picture',
      () async {
    SharedPreferences.setMockInitialValues(
        {'nudge_avreq_$user': ago(const Duration(hours: 1))});
    final cooldown = RequestCooldownService();
    expect(await cooldown.shouldRequestAvatar(user), isFalse);
    expect(await cooldown.shouldRequestAvatar(user, haveAvatar: false), isTrue);
  });

  test('without a picture, the next request waits 30 minutes', () async {
    SharedPreferences.setMockInitialValues(
        {'nudge_avreq_$user': ago(const Duration(minutes: 10))});
    expect(
        await RequestCooldownService()
            .shouldRequestAvatar(user, haveAvatar: false),
        isFalse);
  });

  test('a "no picture set" answer blocks a week, six hours without a picture',
      () async {
    SharedPreferences.setMockInitialValues(
        {'nudge_avabsent_$user': ago(const Duration(days: 1))});
    final cooldown = RequestCooldownService();
    expect(await cooldown.shouldRequestAvatar(user), isFalse);
    expect(await cooldown.shouldRequestAvatar(user, haveAvatar: false), isTrue);

    SharedPreferences.setMockInitialValues(
        {'nudge_avabsent_$user': ago(const Duration(hours: 2))});
    expect(
        await RequestCooldownService()
            .shouldRequestAvatar(user, haveAvatar: false),
        isFalse);
  });
}
