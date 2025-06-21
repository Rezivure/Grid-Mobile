import 'package:matrix/matrix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class AvatarAnnouncementService {
  final Client client;
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();

  AvatarAnnouncementService(this.client);

  /// Announce user profile picture update to a specific room
  Future<void> announceProfPicToRoom(String roomId) async {
    try {
      final room = client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) {
        print('[Avatar Announcement] Skipping room $roomId - not a member');
        return;
      }

      final userId = client.userID;
      if (userId == null) {
        print('[Avatar Announcement] No user ID found');
        return;
      }

      // Check secure storage for avatar data
      final avatarDataStr = await secureStorage.read(key: 'avatar_$userId');
      if (avatarDataStr == null) {
        print('[Avatar Announcement] No avatar data found for user $userId');
        return;
      }

      final avatarData = json.decode(avatarDataStr);
      final uri = avatarData['uri'];
      final key = avatarData['key'];
      final iv = avatarData['iv'];

      if (uri == null || key == null || iv == null) {
        print('[Avatar Announcement] Incomplete avatar data');
        return;
      }

      // Create avatar announcement message
      final eventContent = {
        'msgtype': 'm.avatar.announcement',
        'body': 'Profile picture updated',
        'avatar_url': uri,
        'encryption': {
          'algorithm': 'AES-256',
          'key': key,
          'iv': iv,
        },
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      // Send the announcement
      await room.sendEvent(eventContent);
      print('[Avatar Announcement] Sent profile pic announcement to room ${room.name} ($roomId)');
    } catch (e) {
      print('[Avatar Announcement] Error sending to room $roomId: $e');
    }
  }

  /// Announce group avatar update to a specific room
  Future<void> announceGroupAvatarToRoom(String roomId) async {
    try {
      final room = client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) {
        print('[Group Avatar Announcement] Skipping room $roomId - not a member');
        return;
      }

      // Check secure storage for group avatar data
      final avatarDataStr = await secureStorage.read(key: 'group_avatar_$roomId');
      if (avatarDataStr == null) {
        print('[Group Avatar Announcement] No avatar data found for room $roomId');
        return;
      }

      final avatarData = json.decode(avatarDataStr);
      final uri = avatarData['uri'];
      final key = avatarData['key'];
      final iv = avatarData['iv'];

      if (uri == null || key == null || iv == null) {
        print('[Group Avatar Announcement] Incomplete avatar data');
        return;
      }

      // Create group avatar announcement message
      final eventContent = {
        'msgtype': 'm.group.avatar.announcement',
        'body': 'Group picture updated',
        'avatar_url': uri,
        'encryption': {
          'algorithm': 'AES-256',
          'key': key,
          'iv': iv,
        },
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      // Send the announcement
      await room.sendEvent(eventContent);
      print('[Group Avatar Announcement] Sent group avatar announcement to room ${room.name} ($roomId)');
    } catch (e) {
      print('[Group Avatar Announcement] Error sending to room $roomId: $e');
    }
  }

  /// Broadcast user profile picture to all joined rooms
  Future<void> broadcastProfPicToAllRooms() async {
    try {
      final rooms = client.rooms.where((room) => 
        room.membership == Membership.join && 
        room.name.startsWith('Grid:')
      ).toList();

      print('[Avatar Announcement] Broadcasting profile pic to ${rooms.length} rooms');
      
      for (final room in rooms) {
        await announceProfPicToRoom(room.id);
        // Small delay to avoid rate limiting
        await Future.delayed(Duration(milliseconds: 100));
      }
    } catch (e) {
      print('[Avatar Announcement] Error broadcasting: $e');
    }
  }
}