import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:unifiedpush/unifiedpush.dart';

import 'push/unifiedpush_background_handler.dart';

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

    // Tighten push rules so non-allowlisted events don't even reach
    // sygnal/APNs. The NSE alone can't truly suppress — it only mutates
    // content; iOS still renders the original `default_payload` alert
    // (a single space) when the NSE returns empty content. The right
    // place to filter is server-side push rules.
    await _applyAllowlistPushRules();
  }

  /// Apply the allowlist policy via Matrix push rules:
  ///
  /// - Add an OVERRIDE rule that notifies on `m.room.member` events with
  ///   `content.membership == "join"` (Element-iOS pattern: the join
  ///   event itself drives the push, no synthetic message needed).
  ///   Matches ahead of the spec's `.m.rule.member_event` default
  ///   (which is `dont_notify`).
  /// - Leave `.m.rule.invite_for_me` at its default (enabled) so invites
  ///   still push — no explicit rule needed.
  /// - Disable the spec defaults that push every regular message
  ///   (`.m.rule.message`, `.m.rule.room_one_to_one`,
  ///   `.m.rule.encrypted`, `.m.rule.encrypted_room_one_to_one`). Until
  ///   we implement NSE decryption for chat messages, we don't want any
  ///   push for regular messages.
  ///
  /// All calls are idempotent and survive across logins.
  ///
  /// See https://spec.matrix.org/v1.11/client-server-api/#conditions for
  /// condition semantics.
  Future<void> _applyAllowlistPushRules() async {
    // OVERRIDE rule: notify on member join events. `event_match` doesn't
    // support OR between conditions, so this rule only covers joins; the
    // invite case is already handled by the spec's `.m.rule.invite_for_me`
    // default, which we deliberately leave enabled.
    try {
      await client.request(
        RequestType.PUT,
        '/client/v3/pushrules/global/override/grid.member.join',
        data: {
          'actions': ['notify'],
          'conditions': [
            {
              'kind': 'event_match',
              'key': 'type',
              'pattern': 'm.room.member',
            },
            {
              'kind': 'event_match',
              'key': 'content.membership',
              'pattern': 'join',
            },
          ],
        },
      );
      debugPrint('[Push] Override rule grid.member.join set');
    } catch (e) {
      debugPrint('[Push] Failed to set grid.member.join rule: $e');
    }

    // Disable underride defaults that would otherwise push regular
    // messages. Without these, regular m.room.message / m.room.encrypted
    // events match no rule and don't push at all (truly silent — no
    // blank banner, NSE never invoked).
    for (final ruleId in const <String>[
      '.m.rule.message',
      '.m.rule.room_one_to_one',
      '.m.rule.encrypted',
      '.m.rule.encrypted_room_one_to_one',
    ]) {
      try {
        await client.request(
          RequestType.PUT,
          '/client/v3/pushrules/global/underride/$ruleId/enabled',
          data: {'enabled': false},
        );
        debugPrint('[Push] Disabled underride $ruleId');
      } catch (e) {
        debugPrint('[Push] Failed to disable $ruleId: $e');
      }
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
    // `aps` dict, so iOS drops the push silently (NSE never runs). Need
    // BOTH `mutable-content: 1` and an `alert` for iOS to invoke the NSE
    // — pushes with `mutable-content` only get treated as silent and the
    // NSE is skipped, so there's no chance to classify or render. Keep a
    // placeholder body and rely on the NSE's `suppressNotification` path
    // (passive interruption + empty title/body) to keep suppressed events
    // quiet, while allowlisted events overwrite the placeholder.
    final defaultPayload = <String, dynamic>{
      'aps': <String, dynamic>{
        'mutable-content': 1,
        'alert': <String, dynamic>{
          'body': ' ',
        },
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
  ///
  /// Uses the dedicated `google_api_availability` plugin first because
  /// `FirebaseMessaging.getToken()` can hang indefinitely on GrapheneOS
  /// (where GMS is missing AND microG isn't installed) — the firebase
  /// SDK quietly retries forever waiting for a registration response
  /// that never arrives. Only fall back to a token probe if the GMS
  /// check itself errors out (e.g. the platform plugin failed to load).
  Future<bool> _hasGooglePlayServices() async {
    try {
      final status = await GoogleApiAvailability.instance
          .checkGooglePlayServicesAvailability();
      // `success` means GMS is installed and ready. Every other state —
      // missing, disabled, updating, version-too-old, invalid signature,
      // or "not available on this platform" (degoogled ROMs) — should
      // route to UnifiedPush so we never block on an FCM call that
      // can't possibly resolve.
      if (status == GooglePlayServicesAvailability.success) {
        return true;
      }
      debugPrint('[Push] Google Play Services unavailable: $status');
      return false;
    } catch (e) {
      debugPrint('[Push] GMS availability check failed, probing FCM: $e');
      // Fallback path: bound the token probe so we don't hang forever.
      try {
        final token = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 10));
        return token != null;
      } catch (_) {
        return false;
      }
    }
  }

  /// Get UnifiedPush / ntfy endpoint URL (Android without GMS).
  ///
  /// The UnifiedPush flow:
  ///   1. Initialise the plugin's callbacks. `onMessage` MUST be a
  ///      top-level function (`unifiedPushBackgroundHandler`) — the OS may
  ///      wake a fresh isolate via `--unifiedpush-bg` and resolve the
  ///      callback by name, so any closure / instance method would fail.
  ///   2. Pick a distributor. We try the user's saved distributor first;
  ///      if none is saved we fall back to the system default. If the
  ///      device has zero distributors installed we throw — the user
  ///      needs to install one (e.g. ntfy-android, conversations,
  ///      Google's embedded distributor).
  ///   3. Call `register()`. The distributor will call back into us
  ///      asynchronously via `onNewEndpoint` with the URL we should
  ///      hand to Synapse as our pushkey.
  ///   4. Wait for the endpoint with a 15s timeout. The UP spec doesn't
  ///      bound this — distributors can take their sweet time talking
  ///      to their server (especially ntfy on a cold-started device) —
  ///      but 15s is a reasonable upper bound for app startup.
  Future<String> _getUnifiedPushEndpoint() async {
    final endpointCompleter = Completer<String>();

    // Plugin-wide callback registration. Idempotent — `unifiedpush` keeps
    // a single static registry and overwrites callbacks on re-init.
    //
    // NOTE: we use a closure here only to bridge `onNewEndpoint` into
    // the Completer. `onMessage` deliberately points at the TOP-LEVEL
    // `unifiedPushBackgroundHandler` so the headless engine can find it
    // by name — a closure here would not survive `--unifiedpush-bg`.
    final alreadyRegistered = await UnifiedPush.initialize(
      onNewEndpoint: (PushEndpoint endpoint, String instance) {
        debugPrint(
          '[Push][UP] onNewEndpoint instance=$instance url=${endpoint.url}',
        );
        if (!endpointCompleter.isCompleted) {
          endpointCompleter.complete(endpoint.url);
        }
      },
      onRegistrationFailed: (FailedReason reason, String instance) {
        debugPrint(
          '[Push][UP] onRegistrationFailed instance=$instance reason=$reason',
        );
        if (!endpointCompleter.isCompleted) {
          endpointCompleter.completeError(
            Exception('UnifiedPush registration failed: $reason'),
          );
        }
      },
      onUnregistered: (String instance) {
        debugPrint('[Push][UP] onUnregistered instance=$instance');
      },
      onMessage: unifiedPushBackgroundHandler,
      onTempUnavailable: (String instance) {
        debugPrint('[Push][UP] onTempUnavailable instance=$instance');
      },
    );

    // Pick a distributor. `tryUseCurrentOrDefaultDistributor` returns
    // true if either the previously-saved choice or the system default
    // is available; false means the device has zero installed
    // distributors and the user must install one.
    final pickedDistributor =
        await UnifiedPush.tryUseCurrentOrDefaultDistributor();
    if (!pickedDistributor) {
      throw Exception(
        'No UnifiedPush distributor installed. '
        'Install ntfy-android (or any UP distributor) and re-launch.',
      );
    }

    debugPrint(
      '[Push][UP] initialize complete (alreadyRegistered=$alreadyRegistered), '
      'distributor=${await UnifiedPush.getDistributor()}',
    );

    // Kick off the registration. The distributor will respond
    // asynchronously via `onNewEndpoint`.
    await UnifiedPush.register(instance: 'grid');

    return endpointCompleter.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException(
        'UnifiedPush distributor did not return an endpoint within 15s',
      ),
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
