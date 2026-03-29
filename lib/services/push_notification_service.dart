import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for registering/unregistering Matrix push notification
/// pushers with Synapse via the Matrix SDK's built-in `postPusher` /
/// `deletePusher` helpers.
///
/// Supports three push transports:
///   1. APNs (iOS) — via Sygnal
///   2. FCM  (Android w/ Google Play Services) — via Sygnal
///   3. UnifiedPush / ntfy (Android w/o Google Play Services) — direct HTTP pusher
///
/// Uses `event_id_only` format so Synapse never sends cleartext event content
/// over the push channel (critical for E2EE rooms).
class PushNotificationService {
  final Client client;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// Sygnal push gateway URL (APNs & FCM).
  /// Override via env/config; defaults to the internal cluster gateway.
  final String sygnalUrl;

  /// UnifiedPush / ntfy gateway URL (used when GMS is unavailable).
  static const String _ntfyGatewayUrl =
      'https://push.mygrid.app/_matrix/push/v1/notify';

  static const String _iosAppId = 'app.mygrid.grid.ios';
  static const String _androidFcmAppId = 'app.mygrid.grid.android';
  static const String _androidUnifiedPushAppId =
      'app.mygrid.grid.android.unifiedpush';

  static const String _appDisplayName = 'Grid';
  static const String _prefsKeyPushTransport = 'push_transport';
  static const String _prefsKeyPushkey = 'push_pushkey';
  static const String _prefsKeyPushAppId = 'push_app_id';

  PushNotificationService({
    required this.client,
    this.sygnalUrl = 'https://sygnal.internal.mygrid.app/_matrix/push/v1/notify',
  });

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Call after login / on app startup once the Matrix [client] is logged in.
  ///
  /// Determines the appropriate push transport, obtains a push key (device
  /// token / registration token / ntfy endpoint), and registers a pusher with
  /// the homeserver.
  Future<void> register() async {
    if (!client.isLogged()) {
      debugPrint('[Push] Client not logged in — skipping pusher registration');
      return;
    }

    try {
      final PusherConfig config = await _detectPusherConfig();
      await _setPusher(config);
      await _persistConfig(config);
      debugPrint('[Push] Pusher registered: ${config.transport} / ${config.appId}');
    } catch (e, st) {
      debugPrint('[Push] Failed to register pusher: $e\n$st');
    }
  }

  /// Call on logout to remove this device's pusher from Synapse.
  Future<void> unregister() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pushkey = prefs.getString(_prefsKeyPushkey);
      final appId = prefs.getString(_prefsKeyPushAppId);

      if (pushkey != null && appId != null) {
        await client.deletePusher(PusherId(appId: appId, pushkey: pushkey));
        debugPrint('[Push] Pusher removed: $appId');
      }

      await prefs.remove(_prefsKeyPushTransport);
      await prefs.remove(_prefsKeyPushkey);
      await prefs.remove(_prefsKeyPushAppId);
    } catch (e) {
      debugPrint('[Push] Failed to unregister pusher: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<PusherConfig> _detectPusherConfig() async {
    if (Platform.isIOS) {
      final token = await _getApnsToken();
      return PusherConfig(
        transport: PushTransport.apns,
        appId: _iosAppId,
        pushkey: token,
        dataUrl: Uri.parse(sygnalUrl),
      );
    }

    // Android
    if (await _hasGooglePlayServices()) {
      final token = await _getFcmToken();
      return PusherConfig(
        transport: PushTransport.fcm,
        appId: _androidFcmAppId,
        pushkey: token,
        dataUrl: Uri.parse(sygnalUrl),
      );
    }

    // No GMS — fall back to UnifiedPush / ntfy
    final endpoint = await _getUnifiedPushEndpoint();
    return PusherConfig(
      transport: PushTransport.unifiedPush,
      appId: _androidUnifiedPushAppId,
      pushkey: endpoint, // ntfy topic URL
      dataUrl: Uri.parse(_ntfyGatewayUrl),
    );
  }

  Future<void> _setPusher(PusherConfig config) async {
    final deviceName = await _deviceDisplayName();

    final pusher = Pusher(
      appId: config.appId,
      pushkey: config.pushkey,
      appDisplayName: _appDisplayName,
      deviceDisplayName: deviceName,
      lang: 'en',
      kind: 'http',
      data: PusherData(
        url: config.dataUrl,
        format: 'event_id_only',
      ),
    );

    await client.postPusher(pusher, append: false);
  }

  Future<void> _persistConfig(PusherConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyPushTransport, config.transport.name);
    await prefs.setString(_prefsKeyPushkey, config.pushkey);
    await prefs.setString(_prefsKeyPushAppId, config.appId);
  }

  // ---------------------------------------------------------------------------
  // Platform token helpers
  //
  // These methods contain the actual platform calls. They are isolated so the
  // rest of the service compiles without hard-depending on firebase_messaging
  // or unifiedpush at import time (the packages are still required at runtime).
  // ---------------------------------------------------------------------------

  /// Get APNs device token (iOS).
  ///
  /// Uses `firebase_messaging` which, on iOS, returns the raw APNs token when
  /// configured with an APNs key/cert in Sygnal.
  Future<String> _getApnsToken() async {
    // NOTE: Requires firebase_messaging to be added to pubspec.yaml
    // and FirebaseApp.configure() called in main.dart.
    //
    // Implementation:
    //   import 'package:firebase_messaging/firebase_messaging.dart';
    //   final messaging = FirebaseMessaging.instance;
    //   await messaging.requestPermission();
    //   final token = await messaging.getAPNSToken();
    //   // Fallback to FCM token if APNs token not available directly
    //   return token ?? (await messaging.getToken())!;

    throw UnimplementedError(
      'APNs token retrieval not yet wired. '
      'See comments above for firebase_messaging integration.',
    );
  }

  /// Get FCM registration token (Android with GMS).
  Future<String> _getFcmToken() async {
    // NOTE: Requires firebase_messaging to be added to pubspec.yaml.
    //
    // Implementation:
    //   import 'package:firebase_messaging/firebase_messaging.dart';
    //   final messaging = FirebaseMessaging.instance;
    //   final token = await messaging.getToken();
    //   return token!;

    throw UnimplementedError(
      'FCM token retrieval not yet wired. '
      'See comments above for firebase_messaging integration.',
    );
  }

  /// Check for Google Play Services availability on Android.
  Future<bool> _hasGooglePlayServices() async {
    // NOTE: Requires google_api_availability package or a method channel.
    //
    // Implementation:
    //   import 'package:google_api_availability/google_api_availability.dart';
    //   final availability = await GoogleApiAvailability.instance
    //       .checkGooglePlayServicesAvailability();
    //   return availability == GooglePlayServicesAvailability.success;

    // Default: assume GMS present. Override once package is added.
    return true;
  }

  /// Get UnifiedPush / ntfy endpoint URL (Android without GMS).
  Future<String> _getUnifiedPushEndpoint() async {
    // NOTE: Requires unifiedpush package.
    //
    // Implementation:
    //   import 'package:unifiedpush/unifiedpush.dart';
    //   final completer = Completer<String>();
    //   UnifiedPush.initialize(
    //     onNewEndpoint: (endpoint, _) => completer.complete(endpoint),
    //     onRegistrationFailed: (_) => completer.completeError('UP registration failed'),
    //   );
    //   await UnifiedPush.registerAppWithDialog();
    //   return await completer.future;

    throw UnimplementedError(
      'UnifiedPush endpoint retrieval not yet wired. '
      'See comments above for unifiedpush integration.',
    );
  }

  Future<String> _deviceDisplayName() async {
    // Use Matrix device display name if available, else platform default.
    final deviceId = client.deviceID;
    if (deviceId != null) {
      try {
        final device = await client.getDevice(deviceId);
        if (device.displayName != null) return device.displayName!;
      } catch (_) {}
    }
    return Platform.isIOS ? 'iOS Device' : 'Android Device';
  }
}

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

enum PushTransport { apns, fcm, unifiedPush }

class PusherConfig {
  final PushTransport transport;
  final String appId;
  final String pushkey;
  final Uri dataUrl;

  const PusherConfig({
    required this.transport,
    required this.appId,
    required this.pushkey,
    required this.dataUrl,
  });
}
