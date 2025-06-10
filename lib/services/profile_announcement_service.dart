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
        return;
      }
      
      // Get current profile picture metadata
      final metadata = await profilePictureService.getProfilePictureMetadata();
      if (metadata == null) {
        print('No profile picture to announce');
        return;
      }
      
      final room = client.getRoomById(roomId);
      if (room == null) return;
      
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
}