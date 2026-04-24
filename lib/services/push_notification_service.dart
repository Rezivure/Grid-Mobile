import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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
    this.sygnalUrl = 'http://sygnal.matrix.svc.cluster.local:5000/_matrix/push/v1/notify',
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

    // Reset any push rule overrides we previously installed when we
    // tried to gate joins server-side. We now use synthetic
    // `grid.member.join` messages instead, which push via the
    // standard `.m.rule.message` rule and are gated by the NSE.
    await _resetCustomPushRules();
  }

  /// Idempotently undo PR #222/#223:
  /// - delete the `grid.member.join` override rule (no longer needed)
  /// - re-enable `.m.rule.member_event` (we no longer want every member
  ///   event to fire; the spec default of suppressing them is correct)
  Future<void> _resetCustomPushRules() async {
    try {
      await client.request(
        RequestType.DELETE,
        '/client/v3/pushrules/global/override/grid.member.join',
      );
      debugPrint('[Push] Removed override rule grid.member.join');
    } catch (_) {
      // 404 if it never existed for this user — fine.
    }
    try {
      await client.request(
        RequestType.PUT,
        '/client/v3/pushrules/global/override/.m.rule.member_event/enabled',
        data: {'enabled': true},
      );
      debugPrint('[Push] Re-enabled default .m.rule.member_event');
    } catch (e) {
      debugPrint('[Push] Failed to re-enable .m.rule.member_event: $e');
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

    // `default_payload` is a sygnal feature merged into every APNs payload.
    // With `format: event_id_only` Sygnal by default emits a payload with no
    // `aps` dict, so iOS drops the push silently (NSE never runs). We force
    // `mutable-content: 1` so the NSE gets invoked.
    //
    // We deliberately do NOT include an `alert` here. Without an alert, iOS
    // only renders a banner if the NSE actively *adds* one. That's exactly
    // what we want under the allowlist policy: events the NSE classifier
    // approves get a banner; everything else is silent. (When we did set
    // a placeholder alert, the NSE's "suppress" path leaked an empty
    // banner because iOS still rendered the original alert.)
    final defaultPayload = <String, dynamic>{
      'aps': <String, dynamic>{
        'mutable-content': 1,
      },
    };

    final pusherData = PusherData(
      url: config.dataUrl,
      format: 'event_id_only',
    );

    // APNs-only knob. FCM / UnifiedPush ignore it; Sygnal's FCM path has its
    // own default payload semantics we don't need to touch yet.
    if (config.transport == PushTransport.apns) {
      pusherData.additionalProperties = <String, Object?>{
        ...pusherData.additionalProperties,
        'default_payload': defaultPayload,
      };
    }

    final pusher = Pusher(
      appId: config.appId,
      pushkey: config.pushkey,
      appDisplayName: _appDisplayName,
      deviceDisplayName: deviceName,
      lang: 'en',
      kind: 'http',
      data: pusherData,
    );

    final pushkeyPreview = config.pushkey.length > 20
        ? '${config.pushkey.substring(0, 20)}...'
        : config.pushkey;
    debugPrint(
      '[Push] About to post pusher: '
      'appId=${config.appId}, '
      'pushkey=$pushkeyPreview, '
      'url=${config.dataUrl}',
    );

    await client.postPusher(pusher, append: false);

    debugPrint('[Push] postPusher completed without exception');

    try {
      final pushers = await client.getPushers() ?? <Pusher>[];
      debugPrint('[Push] Synapse returned ${pushers.length} pushers');

      for (final existing in pushers) {
        final existingPreview = existing.pushkey.length > 20
            ? '${existing.pushkey.substring(0, 20)}...'
            : existing.pushkey;
        debugPrint(
          '[Push] Existing pusher: '
          'appId=${existing.appId}, '
          'pushkey=$existingPreview',
        );
      }
    } catch (e, st) {
      debugPrint('[Push] Failed to fetch pushers after registration: $e\n$st');
    }
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
  Future<String> _getApnsToken() async {
    final messaging = FirebaseMessaging.instance;
    // Request permission first
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[Push] iOS permission status: ${settings.authorizationStatus}');
    
    // Wait for APNs token — can take several seconds on first run
    String? apnsToken;
    for (int i = 0; i < 30; i++) {
      apnsToken = await messaging.getAPNSToken();
      if (apnsToken != null) break;
      debugPrint('[Push] Waiting for APNs token... attempt ${i + 1}/30');
      await Future.delayed(const Duration(seconds: 1));
    }
    if (apnsToken != null) {
      debugPrint('[Push] Got APNs token: ${apnsToken.substring(0, 20)}...');
      return apnsToken;
    }
    
    // Try FCM token as fallback (wraps APNs)
    debugPrint('[Push] No APNs token after 30s, trying FCM token...');
    for (int i = 0; i < 5; i++) {
      try {
        final fcmToken = await messaging.getToken();
        if (fcmToken != null) {
          debugPrint('[Push] Got FCM token (fallback): ${fcmToken.substring(0, 20)}...');
          return fcmToken;
        }
      } catch (e) {
        debugPrint('[Push] FCM token attempt ${i + 1} failed: $e');
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    throw Exception('Could not obtain APNs or FCM token after 40s');
  }

  /// Get FCM registration token (Android with GMS).
  Future<String> _getFcmToken() async {
    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken();
    if (token == null) throw Exception('Could not obtain FCM token');
    return token;
  }

  /// Check for Google Play Services availability on Android.
  Future<bool> _hasGooglePlayServices() async {
    try {
      // Try getting FCM token — if it works, GMS is available
      final token = await FirebaseMessaging.instance.getToken();
      return token != null;
    } catch (_) {
      return false;
    }
  }

  /// Get UnifiedPush / ntfy endpoint URL (Android without GMS).
  Future<String> _getUnifiedPushEndpoint() async {
    // TODO: Wire up unifiedpush package when testing on degoogled device
    throw UnimplementedError('UnifiedPush not yet wired for testing');
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
