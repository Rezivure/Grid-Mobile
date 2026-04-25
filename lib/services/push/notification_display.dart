import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'notification_channels.dart';

/// Renders Android push notifications for the three Grid user-visible events:
///
///   1. Room invite to me (`m.room.member`, `membership=invite`, state_key=me)
///        - Grid:Direct: room → "<sender> wants to share location with you"
///        - Grid:Group:  room → "<sender> invited you to <group>"
///   2. Someone joined a group room (`m.room.member`, `membership=join`,
///      sender != me, Grid:Group: room)
///        - → "<sender> joined <group>"
///   3. Friendship invite accepted (`m.room.member`, `membership=join`,
///      sender != me, Grid:Direct: room, prev_membership == 'invite')
///        - → "<sender> accepted your request"
///
/// Everything else is suppressed silently. The server-side push rule
/// (`grid.member.join` override + `.m.rule.invite_for_me` default) should
/// already prevent the push from reaching us; defense-in-depth here too.
///
/// This runs against a Sygnal `event_id_only` payload, so the FCM data
/// message only carries `event_id` + `room_id` (+ counts). To classify
/// anything we must fetch the event from the homeserver via a headless
/// matrix Client — see `fcm_background_handler.dart` for init. If that
/// client is unavailable, we suppress (no "New activity in Grid" noise).
class NotificationDisplay {
  static int _notificationId = 0;

  /// Process an incoming push data message and show appropriate notification.
  ///
  /// [data] is the FCM data payload (Sygnal `event_id_only` format: contains
  /// `event_id`, `room_id`, and optionally counts like `unread`).
  /// [client] is an initialized Matrix client. If null or logged-out we
  /// suppress — the old "New activity in Grid" fallback is gone.
  static Future<void> processAndShow(
    Map<String, dynamic> data,
    matrix.Client? client,
  ) async {
    final eventId = data['event_id'] as String?;
    final roomId = data['room_id'] as String?;

    if (eventId == null || roomId == null) {
      print('[NotificationDisplay] push missing event_id/room_id, suppressing');
      return;
    }

    if (client == null || !client.isLogged()) {
      print('[NotificationDisplay] headless client unavailable, suppressing');
      return;
    }

    try {
      await _fetchAndShow(client, roomId, eventId);
    } catch (e, st) {
      print('[NotificationDisplay] failed to process $eventId in $roomId: $e\n$st');
      // Deliberately suppress on error rather than show a generic banner.
      // A missing key / rate-limit / network blip shouldn't produce
      // "New activity in Grid" spam.
    }
  }

  /// Fetch, decrypt if needed, and classify an event.
  static Future<void> _fetchAndShow(
    matrix.Client client,
    String roomId,
    String eventId,
  ) async {
    final room = client.getRoomById(roomId);
    if (room == null) {
      // Room isn't in our local DB. Could be a fresh invite we haven't
      // synced yet — try to fetch anyway. The CS API endpoint permits
      // reading state when the caller is an invited member.
      print('[NotificationDisplay] no local room for $roomId, suppressing');
      return;
    }

    final matrixEvent = await client.getOneRoomEvent(roomId, eventId);
    var event = matrix.Event.fromMatrixEvent(matrixEvent, room);

    if (event.type == matrix.EventTypes.Encrypted) {
      final enc = client.encryption;
      if (enc == null) {
        print('[NotificationDisplay] encryption not available, suppressing');
        return;
      }
      try {
        event = await enc.decryptRoomEvent(event);
      } catch (e) {
        print('[NotificationDisplay] decrypt failed for $eventId: $e');
        return;
      }
      if (event.type == matrix.EventTypes.Encrypted) {
        // decryptRoomEvent returns the original encrypted event on missing
        // keys instead of throwing. Suppress rather than show ciphertext.
        print(
          '[NotificationDisplay] decrypt yielded still-encrypted event, suppressing',
        );
        return;
      }
    }

    await _classifyAndShow(event, room, client);
  }

  /// Decide which of the three allow-listed cases an event represents and
  /// render the matching banner. Anything unrecognized is suppressed.
  static Future<void> _classifyAndShow(
    matrix.Event event,
    matrix.Room room,
    matrix.Client client,
  ) async {
    final content = event.content;

    // --- Legacy alert types we still want to surface, if they ever arrive ---
    final msgtype = content['msgtype'] as String?;
    if (_isSilent(msgtype)) return;

    if (msgtype == 'm.sos.alert') {
      final sender = await _resolveSenderDisplay(event, room, client);
      await _show(
        title: 'SOS Alert',
        body: '$sender triggered an SOS in ${room.getLocalizedDisplayname()}',
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

    if (msgtype != null && msgtype.startsWith('m.geofence')) {
      final sender = await _resolveSenderDisplay(event, room, client);
      await _show(
        title: 'Geofence Alert',
        body: '$sender triggered a geofence in ${room.getLocalizedDisplayname()}',
        channelId: NotificationChannels.alertsId,
        payload: jsonEncode({
          'room_id': room.id,
          'event_id': event.eventId,
          'type': 'geofence',
        }),
      );
      return;
    }

    // --- Membership events: the bread and butter of the new push policy ---
    if (event.type == 'm.room.member') {
      await _handleMemberEvent(event, room, client);
      return;
    }

    // Anything else reaching this point is unexpected under the allowlist
    // push rules. Stay silent rather than show a generic banner.
    print(
      '[NotificationDisplay] unhandled type=${event.type} msgtype=$msgtype, suppressing',
    );
  }

  /// Handle m.room.member -> invite / join for the three cases above.
  static Future<void> _handleMemberEvent(
    matrix.Event event,
    matrix.Room room,
    matrix.Client client,
  ) async {
    final membership = event.content['membership'] as String?;
    final stateKey = event.stateKey;
    final senderId = event.senderId;
    final myId = client.userID;
    final roomName = room.name;
    final isGrid = roomName.startsWith('Grid:');
    final isDirect =
        roomName.startsWith('Grid:Direct:') || room.isDirectChat;
    final isGroup = roomName.startsWith('Grid:Group:');

    // Non-Grid rooms shouldn't exist in this app, but if they do, suppress.
    if (!isGrid) {
      print('[NotificationDisplay] non-Grid room "$roomName", suppressing');
      return;
    }

    // CASE 1: invite targeting me.
    if (membership == 'invite' && stateKey == myId) {
      final sender = await _resolveSenderDisplay(event, room, client);
      String body;
      if (isDirect) {
        body = '$sender wants to share location with you';
      } else if (isGroup) {
        final pretty = _prettyGroupName(roomName) ?? 'a group';
        body = '$sender invited you to $pretty';
      } else {
        body = '$sender invited you';
      }
      await _show(
        title: 'Grid',
        body: body,
        channelId: NotificationChannels.invitesId,
        payload: jsonEncode({
          'room_id': room.id,
          'event_id': event.eventId,
          'kind': 'invite',
        }),
      );
      return;
    }

    // CASES 2 & 3: a join event. Ignore self-joins.
    if (membership == 'join' && senderId != myId && stateKey == senderId) {
      final prevMembership = event.prevContent?['membership'] as String?;
      final sender = await _resolveSenderDisplay(event, room, client);

      if (isGroup) {
        final pretty = _prettyGroupName(roomName) ?? 'a group';
        await _show(
          title: 'Grid',
          body: '$sender joined $pretty',
          channelId: NotificationChannels.invitesId,
          payload: jsonEncode({
            'room_id': room.id,
            'event_id': event.eventId,
            'kind': 'group_join',
          }),
        );
        return;
      }

      if (isDirect) {
        // Only notify if this join transitions from 'invite' — i.e. the
        // other party just accepted a request we sent. Random joins into
        // a DM room (unlikely, but spec-possible) stay silent.
        if (prevMembership == 'invite') {
          await _show(
            title: 'Grid',
            body: '$sender accepted your request',
            channelId: NotificationChannels.invitesId,
            payload: jsonEncode({
              'room_id': room.id,
              'event_id': event.eventId,
              'kind': 'friend_accept',
            }),
          );
        } else {
          print(
            '[NotificationDisplay] direct-room join without prev=invite, suppressing',
          );
        }
        return;
      }
    }

    // Leaves, profile changes, own joins, etc. — all silent.
    print(
      '[NotificationDisplay] suppressing member event membership=$membership '
      'stateKey=$stateKey sender=$senderId',
    );
  }

  /// Resolve a friendly sender display name. Prefers the in-memory room
  /// member state (populated by prior foreground sync), falls back to a
  /// profile fetch, then to the MXID localpart.
  static Future<String> _resolveSenderDisplay(
    matrix.Event event,
    matrix.Room room,
    matrix.Client client,
  ) async {
    try {
      final m = event.senderFromMemoryOrFallback;
      final dn = m.displayName;
      if (dn != null && dn.isNotEmpty) return dn;
    } catch (_) {}
    try {
      final profile = await client.getUserProfile(event.senderId);
      final dn = profile.displayname;
      if (dn != null && dn.isNotEmpty) return dn;
    } catch (_) {}
    return _localpart(event.senderId) ?? 'Someone';
  }

  /// Returns true if this msgtype is an internal Grid helper that should
  /// never notify (location pings, avatar sync, icon state, etc.).
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

  /// Extract the human-readable group name from
  /// "Grid:Group:<expirationTs>:<groupName>:<creatorId>". Returns null if
  /// the input doesn't match the expected shape. Mirrors parsing in
  /// `lib/utilities/utils.dart::extractExpirationTimestamp`.
  static String? _prettyGroupName(String? raw) {
    if (raw == null || !raw.startsWith('Grid:Group:')) return null;
    final rest = raw.substring('Grid:Group:'.length);
    final parts = rest.split(':');
    // Expected: [<expiration>, <groupName>, <creatorId-left>, <creatorId-right>]
    // or at minimum [<expiration>, <groupName>, ...]
    if (parts.length < 2) return null;
    final group = parts[1].trim();
    return group.isEmpty ? null : group;
  }

  /// "@alice:server" -> "alice"; null on null; passthrough otherwise.
  static String? _localpart(String? mxid) {
    if (mxid == null) return null;
    if (!mxid.startsWith('@')) return mxid;
    final colon = mxid.indexOf(':');
    if (colon <= 1) return mxid.substring(1);
    return mxid.substring(1, colon);
  }
}
