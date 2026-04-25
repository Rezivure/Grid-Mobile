import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/matrix.dart' as matrix;
import 'package:unifiedpush/unifiedpush.dart';

import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/services/backwards_compatibility_service.dart';

import 'notification_channels.dart';
import 'notification_display.dart';

// ---------------------------------------------------------------------------
// UnifiedPush background handler
//
// Mirrors `fcm_background_handler.dart` exactly in spirit: spin up a headless
// Matrix client (or reuse a cached one), hand the parsed Matrix push payload
// to `NotificationDisplay.processAndShow`, let it decrypt + classify against
// the same allowlist, and render the same banner styles.
//
// The shape of an incoming payload differs from FCM, however:
//
// FCM (firebase_messaging) hands us a `RemoteMessage` whose `.data` is already
//   `Map<String, dynamic>` — Sygnal's `event_id_only` payload (event_id,
//   room_id, counts).
//
// UnifiedPush (RFC 8030 + RFC 8291) hands us a `PushMessage` whose `.content`
//   is a `Uint8List` of the *decrypted* Web-Push body. Our gateway
//   (https://push.mygrid.app/_matrix/push/v1/notify) is a Sygnal-equivalent
//   that translates Synapse's `/_matrix/push/v1/notify` JSON into a Web Push
//   POST aimed at the device's UP endpoint URL. The body is the same
//   `event_id_only` JSON; we just have to UTF-8 decode + JSON parse it
//   ourselves.
//
// If decryption failed (`message.decrypted == false`), the body is
// ciphertext we can't read — suppress, don't crash.
// ---------------------------------------------------------------------------

// Cache the Matrix client + databases across consecutive UP deliveries inside
// the same isolate. UP can deliver bursts (a single distributor wake can
// drain queued pushes) and re-init is expensive (vodozemac native lib +
// sqlite open + Matrix client init).  Mirrors the cache in
// fcm_background_handler.dart and android_background_task.dart.
matrix.Client? _cachedClient;
DatabaseService? _cachedDatabaseService;
matrix.DatabaseApi? _cachedDatabase;

/// Top-level callback invoked by the `unifiedpush` plugin on every push
/// message — both foreground and background isolate. Must be a top-level
/// function (no instance state, no closure capture) so the Dart VM can
/// resolve it from the `--unifiedpush-bg` headless engine entrypoint.
///
/// Wired up via `UnifiedPush.initialize(onMessage: unifiedPushBackgroundHandler, ...)`
/// in `PushNotificationService._getUnifiedPushEndpoint()`.
@pragma('vm:entry-point')
Future<void> unifiedPushBackgroundHandler(
  PushMessage message,
  String instance,
) async {
  // Ensure notification channels exist on this isolate. The umbrella
  // `NotificationChannels.createAll()` re-initialises the local-notifications
  // plugin idempotently — safe to call from a headless engine.
  await NotificationChannels.createAll();

  if (!message.decrypted) {
    debugPrint(
      '[UnifiedPush BG] message decryption failed (instance=$instance), '
      'suppressing — distributor or our pubKeySet is out of date',
    );
    return;
  }

  // Decode the Web-Push body as UTF-8 JSON. Our push gateway uses the
  // standard Matrix push payload (Sygnal's `event_id_only`):
  //   { "notification": { "event_id": "...", "room_id": "...", ... } }
  // Some gateways flatten this into the top level; handle both shapes.
  final Map<String, dynamic> data;
  try {
    final raw = utf8.decode(message.content);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      debugPrint('[UnifiedPush BG] payload is not a JSON object, suppressing');
      return;
    }
    final notification = decoded['notification'];
    if (notification is Map<String, dynamic>) {
      data = notification;
    } else {
      data = decoded;
    }
  } catch (e) {
    debugPrint('[UnifiedPush BG] failed to parse payload: $e');
    return;
  }

  matrix.Client? client;
  try {
    client = await _initHeadlessMatrixClient();
  } catch (e) {
    debugPrint('[UnifiedPush BG] failed to init headless client: $e');
  }

  await NotificationDisplay.processAndShow(data, client);
}

/// Initialize a minimal Matrix client for background decryption.
///
/// Reuses the SAME database path as the foreground app
/// (`getApplicationSupportDirectory()/grid_app_matrix.db`) via
/// `BackwardsCompatibilityService.createMatrixDatabase()`, so megolm
/// session keys written by the foreground client are immediately
/// available here for `decryptAndVerify()`.
///
/// Returns null if init fails for any reason — caller handles fallback.
Future<matrix.Client?> _initHeadlessMatrixClient() async {
  if (_cachedClient != null) {
    return _cachedClient;
  }

  debugPrint('[UnifiedPush BG] Initializing headless Matrix client (cold start)');

  // Vodozemac (olm-replacement native lib) MUST be initialized in every
  // isolate before the matrix Client touches any encryption code paths.
  // The foreground isolate does this in main.dart; background isolates
  // (FCM handler, libre_location headless task, this UP handler) each
  // need their own init. `vod.init()` is idempotent.
  await vod.init();

  _cachedDatabaseService = DatabaseService();
  await _cachedDatabaseService!.initDatabase();

  _cachedDatabase = await BackwardsCompatibilityService.createMatrixDatabase();
  final client = matrix.Client(
    'Grid App',
    database: _cachedDatabase!,
  );

  // `client.init()` rehydrates user_id, device_id, access_token, and
  // crypto state from the persisted DB. We do NOT start a sync — we
  // don't want to fight the foreground app for the sync stream when
  // both are alive.
  await client.init();
  client.backgroundSync = false;

  if (!client.isLogged()) {
    debugPrint(
      '[UnifiedPush BG] Headless client init: not logged in, returning null',
    );
    await client.dispose();
    _cachedClient = null;
    _cachedDatabase = null;
    _cachedDatabaseService = null;
    return null;
  }

  _cachedClient = client;
  debugPrint(
    '[UnifiedPush BG] Headless Matrix client ready (user=${client.userID})',
  );
  return client;
}
