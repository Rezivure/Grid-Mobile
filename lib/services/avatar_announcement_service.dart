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

      // Send the announcement - Matrix SDK handles E2EE automatically
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

  /// Send avatar state bundle to new room members
  /// This sends all known avatars for room members to help with initial sync
  Future<void> sendAvatarState(String roomId, {String? targetUserId}) async {
    try {
      final room = client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) {
        print('[Avatar State] Skipping room $roomId - not a member');
        return;
      }

      // Collect avatar data for all room members
      final avatarStates = <Map<String, dynamic>>[];
      final participants = await room.getParticipants();
      
      for (final participant in participants) {
        final userId = participant.id;
        
        // Get avatar data from secure storage
        final avatarDataStr = await secureStorage.read(key: 'avatar_$userId');
        if (avatarDataStr != null) {
          try {
            final avatarData = json.decode(avatarDataStr);
            if (avatarData['uri'] != null && avatarData['key'] != null && avatarData['iv'] != null) {
              avatarStates.add({
                'user_id': userId,
                'avatar_url': avatarData['uri'],
                'encryption': {
                  'algorithm': 'AES-256',
                  'key': avatarData['key'],
                  'iv': avatarData['iv'],
                },
              });
            }
          } catch (e) {
            print('[Avatar State] Error parsing avatar data for $userId: $e');
          }
        }
      }

      // Include our own avatar
      final myUserId = client.userID;
      if (myUserId != null) {
        final myAvatarStr = await secureStorage.read(key: 'avatar_$myUserId');
        if (myAvatarStr != null) {
          try {
            final myAvatar = json.decode(myAvatarStr);
            if (myAvatar['uri'] != null && myAvatar['key'] != null && myAvatar['iv'] != null) {
              // Add our avatar if not already in the list
              if (!avatarStates.any((a) => a['user_id'] == myUserId)) {
                avatarStates.add({
                  'user_id': myUserId,
                  'avatar_url': myAvatar['uri'],
                  'encryption': {
                    'algorithm': 'AES-256',
                    'key': myAvatar['key'],
                    'iv': myAvatar['iv'],
                  },
                });
              }
            }
          } catch (e) {
            print('[Avatar State] Error parsing own avatar data: $e');
          }
        }
      }

      if (avatarStates.isEmpty) {
        print('[Avatar State] No avatars to share for room $roomId');
        return;
      }

      // Create avatar state message
      final eventContent = {
        'msgtype': 'm.avatar.state',
        'body': 'Avatar state bundle',
        'avatars': avatarStates,
        'target_user': targetUserId, // Optional: specify recipient
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      // Send the state bundle
      await room.sendEvent(eventContent);
      print('[Avatar State] Sent avatar state with ${avatarStates.length} avatars to room ${room.name} ($roomId)');
    } catch (e) {
      print('[Avatar State] Error sending avatar state to room $roomId: $e');
    }
  }

  /// Request avatars from specific users or all room members
  Future<void> requestAvatars(String roomId, {List<String>? userIds}) async {
    try {
      final room = client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) {
        print('[Avatar Request] Skipping room $roomId - not a member');
        return;
      }

      // Create avatar request message
      final eventContent = {
        'msgtype': 'm.avatar.request',
        'body': 'Requesting avatar updates',
        'requested_users': userIds, // null means request from all
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      // Send the request
      await room.sendEvent(eventContent);
      print('[Avatar Request] Sent avatar request to room ${room.name} ($roomId) for users: ${userIds?.join(", ") ?? "all"}');
    } catch (e) {
      print('[Avatar Request] Error sending request to room $roomId: $e');
    }
  }

  /// Handle incoming avatar request and respond with our avatar
  Future<void> handleAvatarRequest(String roomId, String requesterId, List<String>? requestedUsers) async {
    try {
      final myUserId = client.userID;
      if (myUserId == null) return;

      // Check if we're in the requested users list (or if it's a broadcast request)
      if (requestedUsers != null && !requestedUsers.contains(myUserId)) {
        return; // Request not for us
      }

      // Don't respond to our own requests
      if (requesterId == myUserId) return;

      print('[Avatar Request] Responding to avatar request from $requesterId in room $roomId');
      
      // Send our avatar announcement
      await announceProfPicToRoom(roomId);
    } catch (e) {
      print('[Avatar Request] Error handling request: $e');
    }
  }
}