import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/services/app_lifecycle_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLifecycleChannel.shouldMoveToBackground', () {
    test('backgrounds on Android when the route did not pop (at root)', () {
      expect(
        AppLifecycleChannel.shouldMoveToBackground(
          didPop: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('does nothing on Android when a route was actually popped', () {
      expect(
        AppLifecycleChannel.shouldMoveToBackground(
          didPop: true,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });

    test('does nothing on iOS (no root back gesture to intercept)', () {
      expect(
        AppLifecycleChannel.shouldMoveToBackground(
          didPop: false,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
    });
  });

  group('AppLifecycleChannel.moveTaskToBack', () {
    const channel = MethodChannel(AppLifecycleChannel.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('invokes the native moveTaskToBack method and returns its result',
        () async {
      final invoked = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        invoked.add(call.method);
        return true;
      });

      final result = await AppLifecycleChannel(channel: channel).moveTaskToBack();

      expect(invoked, ['moveTaskToBack']);
      expect(result, isTrue);
    });

    test('fails closed to false when the native side is missing (iOS/old build)',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw MissingPluginException('no native handler');
      });

      final result = await AppLifecycleChannel(channel: channel).moveTaskToBack();

      expect(result, isFalse);
    });

    test('fails closed to false on a PlatformException', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });

      final result = await AppLifecycleChannel(channel: channel).moveTaskToBack();

      expect(result, isFalse);
    });

    test('treats a null native result as not handled', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);

      final result = await AppLifecycleChannel(channel: channel).moveTaskToBack();

      expect(result, isFalse);
    });
  });
}
