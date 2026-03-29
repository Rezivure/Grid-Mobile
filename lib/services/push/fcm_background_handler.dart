import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'notification_channels.dart';
import 'notification_display.dart';

/// Top-level function — MUST be outside any class.
/// Called by FCM when app is killed/background and a data message arrives.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase (required in background isolate)
  await Firebase.initializeApp();

  // Initialize notification channels
  await NotificationChannels.createAll();

  final data = message.data;

  // Try to initialize a headless Matrix client for decryption
  matrix.Client? client;
  try {
    client = await _initHeadlessMatrixClient();
  } catch (_) {
    // If client init fails, we'll show generic notifications
  }

  await NotificationDisplay.processAndShow(data, client);

  // Clean up
  if (client != null) {
    await client.dispose();
  }
}

/// Initialize a minimal Matrix client for background decryption.
/// Reuses stored credentials from flutter_secure_storage / shared_preferences.
///
/// TODO: Adapt this to match Grid-Mobile's actual client initialization.
/// This needs access to the same database and encryption keys as the foreground client.
Future<matrix.Client?> _initHeadlessMatrixClient() async {
  // PLACEHOLDER: Replace with actual Grid-Mobile client init logic.
  // Key requirements:
  // 1. Same database path as foreground client (for Megolm session keys)
  // 2. Same user credentials (access token from secure storage)
  // 3. Vodozemac native library must be loadable in background isolate
  //
  // Look at android_background_task.dart's headless location handler for
  // reference — it already caches a Matrix client in background isolates.
  //
  // For now, return null to trigger generic "New activity in Grid" notifications
  // for encrypted events. Unencrypted m.room.member events will still show
  // full details.
  return null;
}
