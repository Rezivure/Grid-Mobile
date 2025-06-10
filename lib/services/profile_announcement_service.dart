import 'dart:convert';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/services/profile_picture_service.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;

class ProfileAnnouncementService {
  static const String LAST_ANNOUNCE_KEY = 'last_profile_announce';
  static const int ANNOUNCE_INTERVAL_DAYS = 6;
  
  final Client client;
  final ProfilePictureService profilePictureService;
  
  ProfileAnnouncementService({
    required this.client,
    required this.profilePictureService,
  });
  
  /// Announces profile picture to a specific room
  Future<void> announceToRoom(String roomId) async {
    try {
      // Skip if custom homeserver
      if (utils.isCustomHomeserver(client.homeserver.toString())) {
        print('ProfileAnnouncementService: Skipping - custom homeserver');
        return;
      }
      
      final room = client.getRoomById(roomId);
      if (room == null) {
        print('ProfileAnnouncementService: Room not found: $roomId');
        return;
      }
      
      // Check if this is a group room
      final isGroup = room.name.startsWith('Grid:Group:');
      print('ProfileAnnouncementService: Room $roomId is group: $isGroup, name: ${room.name}');
      
      if (isGroup) {
        // For groups, always announce personal profile picture
        // Additionally, if we're an admin and a new member joined, announce group avatar
        final myUserId = client.userID;
        if (myUserId != null) {
          final powerLevel = room.getPowerLevelByUserId(myUserId);
          print('ProfileAnnouncementService: My power level in group: $powerLevel');
          if (powerLevel >= 50) {
            // We're an admin, check if group has an avatar to share
            await _announceGroupAvatarIfExists(roomId);
          }
        }
      }
      
      // For both direct rooms AND groups, announce personal profile
      // Get current profile picture metadata
      final metadata = await profilePictureService.getProfilePictureMetadata();
      if (metadata == null) {
        print('No profile picture to announce');
        return;
      }
      
      // Skip large groups to prevent spam
      if (room.summary.mJoinedMemberCount != null && 
          room.summary.mJoinedMemberCount! > 100) {
        return;
      }
      
      // Create announcement message
      final content = {
        'msgtype': 'grid.profile.announce',
        'body': 'Profile picture updated',
        'profile': {
          'url': metadata['url'],
          'key': metadata['key'],
          'iv': metadata['iv'],
          'version': metadata['version'] ?? '1.0',
          'updated_at': metadata['uploadedAt'],
        }
      };
      
      // Send as encrypted message if room supports it
      await room.sendEvent(content);
      
      print('Announced profile to room: $roomId');
    } catch (e) {
      print('Failed to announce profile to room $roomId: $e');
    }
  }
  
  /// Announces to all active rooms
  Future<void> announceToAllActiveRooms() async {
    try {
      // Skip if custom homeserver
      if (utils.isCustomHomeserver(client.homeserver.toString())) {
        return;
      }
      
      final rooms = client.rooms.where((room) {
        // Only direct chats and small groups
        if (room.summary.mJoinedMemberCount != null && 
            room.summary.mJoinedMemberCount! > 100) {
          return false;
        }
        
        // Skip if no recent activity (30 days)
        final lastEvent = room.lastEvent;
        if (lastEvent != null) {
          final daysSince = DateTime.now().difference(lastEvent.originServerTs).inDays;
          if (daysSince > 30) return false;
        }
        
        return true;
      }).toList();
      
      // Announce with rate limiting
      for (final room in rooms) {
        await announceToRoom(room.id);
        await Future.delayed(Duration(milliseconds: 100)); // Rate limit
      }
      
      // Update last announce time
      await _updateLastAnnounceTime();
    } catch (e) {
      print('Failed to announce to all rooms: $e');
    }
  }
  
  /// Checks if we should announce based on 6-day interval
  Future<bool> shouldAnnounceBasedOnTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastAnnounceMs = prefs.getInt(LAST_ANNOUNCE_KEY) ?? 0;
      
      if (lastAnnounceMs == 0) return true; // Never announced
      
      final lastAnnounce = DateTime.fromMillisecondsSinceEpoch(lastAnnounceMs);
      final daysSince = DateTime.now().difference(lastAnnounce).inDays;
      
      return daysSince >= ANNOUNCE_INTERVAL_DAYS;
    } catch (e) {
      return true; // Announce on error
    }
  }
  
  /// Updates the last announce timestamp
  Future<void> _updateLastAnnounceTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(LAST_ANNOUNCE_KEY, DateTime.now().millisecondsSinceEpoch);
  }
  
  /// Announces group avatar if it exists (for admins when new members join)
  Future<void> _announceGroupAvatarIfExists(String roomId) async {
    try {
      print('ProfileAnnouncementService: Checking for group avatar to announce for room: $roomId');
      final prefs = await SharedPreferences.getInstance();
      final allMetadataStr = prefs.getString('group_avatars_metadata');
      
      if (allMetadataStr == null) {
        print('ProfileAnnouncementService: No group avatars metadata found at all');
        return;
      }
      
      final allMetadata = json.decode(allMetadataStr) as Map<String, dynamic>;
      final groupMetadata = allMetadata[roomId] as Map<String, dynamic>?;
      
      if (groupMetadata == null) {
        print('ProfileAnnouncementService: No group avatar metadata found for room: $roomId');
        return;
      }
      
      // Create group avatar announcement
      final content = {
        'msgtype': 'grid.group.avatar.announce',
        'body': 'Group avatar',
        'avatar': {
          'url': groupMetadata['url'],
          'key': groupMetadata['key'],
          'iv': groupMetadata['iv'],
          'version': groupMetadata['version'] ?? '1.0',
          'updated_at': groupMetadata['updated_at'],
        }
      };
      
      final room = client.getRoomById(roomId);
      if (room != null) {
        await room.sendEvent(content);
        print('Announced group avatar to room: $roomId');
      }
    } catch (e) {
      print('Failed to announce group avatar: $e');
    }
  }
}