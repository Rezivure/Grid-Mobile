import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android notification channel definitions for Grid.
class NotificationChannels {
  static const String invitesId = 'invites';
  static const String membersId = 'members';
  static const String alertsId = 'alerts';
  static const String generalId = 'general';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  /// Create all notification channels. Call once at app startup.
  static Future<void> createAll() async {
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: initAndroid);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        invitesId,
        'Invites',
        description: 'Group invites and share requests',
        importance: Importance.high,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        membersId,
        'Members',
        description: 'Member joins and leaves',
        importance: Importance.defaultImportance,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        alertsId,
        'Alerts',
        description: 'SOS and geofence alerts',
        importance: Importance.max,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        generalId,
        'General',
        description: 'Other notifications',
        importance: Importance.defaultImportance,
      ),
    );
  }

  static void _onNotificationTap(NotificationResponse response) {
    // TODO: Navigate to the relevant room/screen based on response.payload
    // Payload contains JSON with room_id, event_type, etc.
  }
}
