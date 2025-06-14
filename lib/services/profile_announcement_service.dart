import 'dart:convert';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/services/profile_picture_service.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/services/logger_service.dart';

class ProfileAnnouncementService {
  static const String _tag = 'ProfileAnnouncement';
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
        Logger.debug(_tag, 'Skipping - custom homeserver');
        return;
      }
      
      final room = client.getRoomById(roomId);
      if (room == null) {
        Logger.warning(_tag, 'Room not found', data: {'roomId': roomId});
        return;
      }
      
      // Check if this is a group room
      final isGroup = room.name.startsWith('Grid:Group:');
      Logger.debug(_tag, 'Checking room type', data: {
        'roomId': roomId,
        'isGroup': isGroup,
        'name': room.name
      });
      
      if (isGroup) {
        // For groups, always announce personal profile picture
        // Additionally, if we're an admin and a new member joined, announce group avatar
        final myUserId = client.userID;
        if (myUserId != null) {
          final powerLevel = room.getPowerLevelByUserId(myUserId);
          Logger.debug(_tag, 'Power level check', data: {'level': powerLevel});
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
        Logger.debug(_tag, 'No profile picture to announce');
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
      
      Logger.info(_tag, '📸 Profile announced', data: {'roomId': roomId});
    } catch (e) {
      Logger.error(_tag, 'Failed to announce profile: $e', data: {'roomId': roomId});
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
      Logger.error(_tag, 'Failed bulk announcement: $e');
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
      Logger.debug(_tag, 'Checking for group avatar to announce', data: {'roomId': roomId});
      final prefs = await SharedPreferences.getInstance();
      final allMetadataStr = prefs.getString('group_avatars_metadata');
      
      if (allMetadataStr == null) {
        Logger.debug(_tag, 'No group avatars metadata found');
        return;
      }
      
      final allMetadata = json.decode(allMetadataStr) as Map<String, dynamic>;
      final groupMetadata = allMetadata[roomId] as Map<String, dynamic>?;
      
      if (groupMetadata == null) {
        Logger.debug(_tag, 'No group avatar metadata found', data: {'roomId': roomId});
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
        Logger.info(_tag, 'Group avatar announced', data: {'roomId': roomId});
      }
    } catch (e) {
      Logger.error(_tag, 'Failed to announce group avatar: $e');
    }
  }
}