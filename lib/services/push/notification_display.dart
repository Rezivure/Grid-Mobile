import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'notification_channels.dart';

/// Classifies and displays notifications based on Matrix event content.
class NotificationDisplay {
  static int _notificationId = 0;

  /// Process an incoming push data message and show appropriate notification.
  ///
  /// [data] is the FCM/UnifiedPush data payload.
  /// [client] is an initialized Matrix client (may be null in background if
  /// client init fails — in that case we show a generic notification).
  static Future<void> processAndShow(
    Map<String, dynamic> data,
    matrix.Client? client,
  ) async {
    final eventId = data['event_id'] as String?;
    final roomId = data['room_id'] as String?;
    final eventType = data['type'] as String?;
    final unread = int.tryParse(data['unread']?.toString() ?? '') ?? 0;

    if (eventId == null || roomId == null) return;

    // Membership events (unencrypted in push payload from Sygnal)
    if (eventType == 'm.room.member') {
      await _showMemberNotification(data);
      return;
    }

    // Encrypted events — need to fetch and decrypt
    if (eventType == 'm.room.encrypted') {
      if (client == null || !client.isLogged()) {
        await _showGenericNotification(roomId);
        return;
      }
      await _handleEncryptedEvent(client, roomId, eventId);
      return;
    }

    // Unknown event type — show generic if there are unreads
    if (unread > 0) {
      await _showGenericNotification(roomId);
    }
  }

  /// Show notification for m.room.member events.
  /// Sygnal includes sender_display_name, room_name, and membership in the push.
  static Future<void> _showMemberNotification(
    Map<String, dynamic> data,
  ) async {
    final sender = data['sender_display_name'] ?? data['sender'] ?? 'Someone';
    final roomName = data['room_name'] ?? 'a grid';
    final membership = data['membership'] ?? 'join';

    String title;
    String body;
    String channelId;

    switch (membership) {
      case 'invite':
        title = 'New Invite';
        body = '$sender invited you to $roomName';
        channelId = NotificationChannels.invitesId;
        break;
      case 'join':
        title = roomName;
        body = '$sender joined';
        channelId = NotificationChannels.membersId;
        break;
      case 'leave':
        title = roomName;
        body = '$sender left';
        channelId = NotificationChannels.membersId;
        break;
      default:
        title = roomName;
        body = '$sender updated membership';
        channelId = NotificationChannels.generalId;
    }

    await _show(
      title: title,
      body: body,
      channelId: channelId,
      payload: jsonEncode(data),
    );
  }

  /// Fetch, decrypt, and classify an encrypted event.
  static Future<void> _handleEncryptedEvent(
    matrix.Client client,
    String roomId,
    String eventId,
  ) async {
    try {
      final room = client.getRoomById(roomId);
      if (room == null) {
        await _showGenericNotification(roomId);
        return;
      }

      // Fetch the event from the server
      final eventJson = await client.getOneRoomEvent(roomId, eventId);
      var event = matrix.Event.fromJson(eventJson, room);

      // Decrypt if encrypted
      if (event.type == matrix.EventTypes.Encrypted) {
        event = await event.decryptAndVerify();
      }

      // Classify the decrypted content
      await _classifyAndShow(event, room);
    } catch (e) {
      // Decryption failed — show generic
      await _showGenericNotification(roomId);
    }
  }

  /// Classify a decrypted event and show notification (or stay silent).
  static Future<void> _classifyAndShow(
    matrix.Event event,
    matrix.Room room,
  ) async {
    final content = event.content;
    final msgtype = content['msgtype'] as String?;

    // Silent events — no notification
    if (_isSilent(msgtype)) return;

    final roomName = room.getLocalizedDisplayname();

    // SOS alert
    if (msgtype == 'm.sos.alert') {
      final sender = event.senderFromMemoryOrFallback.displayName ??
          event.senderId;
      await _show(
        title: '🆘 SOS Alert',
        body: '$sender triggered an SOS in $roomName',
        channelId: NotificationChannels.alertsId,
        payload: jsonEncode({
          'room_id': room.id,
          'event_id': event.eventId,
          'type': 'sos',
        }),
        priority: Priority.max,
      );
      return;
    }

    // Geofence arrival/event
    if (msgtype != null && msgtype.startsWith('m.geofence')) {
      final sender = event.senderFromMemoryOrFallback.displayName ??
          event.senderId;
      await _show(
        title: '📍 Geofence Alert',
        body: '$sender triggered a geofence in $roomName',
        channelId: NotificationChannels.alertsId,
        payload: jsonEncode({
          'room_id': room.id,
          'event_id': event.eventId,
          'type': 'geofence',
        }),
      );
      return;
    }

    // Any other non-silent encrypted message — show generic
    await _show(
      title: roomName,
      body: 'New activity',
      channelId: NotificationChannels.generalId,
      payload: jsonEncode({
        'room_id': room.id,
        'event_id': event.eventId,
      }),
    );
  }

  /// Returns true if this msgtype should NOT produce a notification.
  static bool _isSilent(String? msgtype) {
    if (msgtype == null) return false;
    const silentTypes = {
      'm.location',
      'm.avatar.announcement',
      'm.group.avatar.announcement',
      'm.avatar.state',
      'm.avatar.request',
      'm.map.icon.create',
      'm.map.icon.update',
      'm.map.icon.delete',
      'm.map.icon.state',
    };
    return silentTypes.contains(msgtype);
  }

  static Future<void> _showGenericNotification(String roomId) async {
    await _show(
      title: 'Grid',
      body: 'New activity in Grid',
      channelId: NotificationChannels.generalId,
      payload: jsonEncode({'room_id': roomId}),
    );
  }

  static Future<void> _show({
    required String title,
    required String body,
    required String channelId,
    String? payload,
    Priority priority = Priority.defaultPriority,
  }) async {
    final id = _notificationId++;

    await NotificationChannels.plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId, // channel name — Android uses the one from createNotificationChannel
          priority: priority,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: payload,
    );
  }
}
