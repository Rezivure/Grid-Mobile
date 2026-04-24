import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// Bridges Matrix credentials from the Flutter side into the iOS App Group
/// `UserDefaults` so the GridNotificationService (NSE) can fetch events via
/// `MatrixAPIClient` when a push arrives.
///
/// Without this, the NSE has no `access_token` / `homeserver_url` and can only
/// fall back to the APNs `default_payload` — i.e. no user-visible notification.
///
/// On Android this is a no-op; the FCM background handler handles hint caching
/// through a different path.
class AppGroupBridge {
  static const MethodChannel _channel =
      MethodChannel('app.mygrid.grid/app_group');

  /// Push the currently logged-in [Client]'s credentials into the App Group
  /// shared defaults. Safe to call on non-iOS platforms (becomes a no-op).
  static Future<void> writeMatrixCredentials(Client client) async {
    if (!Platform.isIOS) return;
    final accessToken = client.accessToken;
    final homeserver = client.homeserver?.toString();
    final userId = client.userID;
    final deviceId = client.deviceID;

    if (accessToken == null || homeserver == null) {
      debugPrint('[AppGroupBridge] Skipping write: missing token/homeserver');
      return;
    }

    try {
      await _channel.invokeMethod('writeMatrixCredentials', <String, String?>{
        'access_token': accessToken,
        'homeserver_url': homeserver,
        'user_id': userId,
        'device_id': deviceId,
      });
      debugPrint('[AppGroupBridge] Credentials mirrored to App Group');
    } catch (e) {
      debugPrint('[AppGroupBridge] Failed to mirror credentials: $e');
    }
  }

  /// Clear credentials from the App Group shared defaults on logout.
  static Future<void> clearMatrixCredentials() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('clearMatrixCredentials');
    } catch (e) {
      debugPrint('[AppGroupBridge] Failed to clear credentials: $e');
    }
  }
}
