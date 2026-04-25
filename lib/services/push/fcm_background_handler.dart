import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/matrix.dart' as matrix;
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/services/backwards_compatibility_service.dart';
import 'notification_channels.dart';
import 'notification_display.dart';

// Reuse the same Matrix client + database across consecutive background
// invocations. Cold-init is expensive (vodozemac native lib + sqlite open +
// Matrix client init) and FCM can deliver bursts of pushes within the
// same isolate; caching keeps the second-and-onward delivery snappy.
//
// Mirrors the cache pattern used by `android_background_task.dart` for
// headless location processing.
matrix.Client? _cachedClient;
DatabaseService? _cachedDatabaseService;
matrix.DatabaseApi? _cachedDatabase;

/// Top-level function — MUST be outside any class.
/// Called by FCM when app is killed/background and a data message arrives.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase (required in background isolate).
  await Firebase.initializeApp();

  // Initialize notification channels.
  await NotificationChannels.createAll();

  final data = message.data;

  // Try to initialize a headless Matrix client for decryption. If this
  // fails, NotificationDisplay falls back to a generic "New activity"
  // banner — never raw ciphertext.
  matrix.Client? client;
  try {
    client = await _initHeadlessMatrixClient();
  } catch (e) {
    print('[FCM Background] Failed to init headless client: $e');
  }

  await NotificationDisplay.processAndShow(data, client);

  // Note: we deliberately do NOT dispose the cached client. It persists
  // across invocations of this background isolate so the next push is
  // fast. The OS reclaims the isolate when it's no longer needed.
}

/// Initialize a minimal Matrix client for background decryption.
///
/// Reuses the SAME database path as the foreground app
/// (`getApplicationSupportDirectory()/grid_app_matrix.db`) via
/// `BackwardsCompatibilityService.createMatrixDatabase()`, so megolm
/// session keys written by the foreground client are immediately
/// available here for `decryptAndVerify()`.
///
/// This intentionally mirrors `android_background_task.dart`'s pattern,
/// which already proves this works in a Dart background isolate
/// (vodozemac loads, sqlite opens, client.init() restores access token
/// and device id from the DB).
///
/// Returns null if init fails for any reason — caller handles fallback.
Future<matrix.Client?> _initHeadlessMatrixClient() async {
  if (_cachedClient != null) {
    return _cachedClient;
  }

  print('[FCM Background] Initializing headless Matrix client (cold start)');

  // Vodozemac (olm-replacement native lib) MUST be initialized in every
  // isolate before the matrix Client touches any encryption code paths.
  // The foreground isolate does this in main.dart; background isolates
  // (FCM handler, libre_location headless task) each need their own init.
  // `vod.init()` is idempotent.
  await vod.init();

  _cachedDatabaseService = DatabaseService();
  await _cachedDatabaseService!.initDatabase();

  _cachedDatabase = await BackwardsCompatibilityService.createMatrixDatabase();
  final client = matrix.Client(
    'Grid App',
    database: _cachedDatabase!,
  );

  // `client.init()` rehydrates the user_id, device_id, access_token, and
  // crypto state (olm account, megolm sessions) from the persisted DB.
  // It does NOT start a sync — we don't want to fight with the foreground
  // app for the sync stream when both are alive.
  await client.init();
  client.backgroundSync = false;

  if (!client.isLogged()) {
    print('[FCM Background] Headless client init: not logged in, returning null');
    await client.dispose();
    _cachedClient = null;
    _cachedDatabase = null;
    _cachedDatabaseService = null;
    return null;
  }

  _cachedClient = client;
  print('[FCM Background] Headless Matrix client ready (user=${client.userID})');
  return client;
}
