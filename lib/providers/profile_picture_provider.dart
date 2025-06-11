import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:grid_frontend/services/others_profile_service.dart';
import 'package:grid_frontend/services/profile_picture_service.dart';
import 'package:matrix/matrix.dart';

class ProfilePictureProvider with ChangeNotifier {
  final OthersProfileService _othersProfileService = OthersProfileService();
  final ProfilePictureService _profilePictureService = ProfilePictureService();
  final Map<String, Uint8List?> _profilePictureCache = {};
  final Map<String, Uint8List?> _groupAvatarCache = {};
  final Set<String> _updatedProfiles = {};
  final Set<String> _updatedGroups = {};
  final Map<String, int> _profileVersions = {};
  final Map<String, int> _groupVersions = {};
  Client? _client;
  
  void setClient(Client client) {
    _client = client;
  }
  
  /// Get profile picture for a user or group
  Future<Uint8List?> getProfilePicture(String userId) async {
    // Check memory cache first
    if (_profilePictureCache.containsKey(userId)) {
      return _profilePictureCache[userId];
    }
    
    // Check if this is the current user
    if (_client != null && userId == _client!.userID) {
      // Load current user's profile picture from ProfilePictureService
      final profileBytes = await _profilePictureService.getLocalProfilePicture();
      if (profileBytes != null) {
        _profilePictureCache[userId] = profileBytes;
        return profileBytes;
      }
    } else {
      // Load from disk cache for other users
      final profileBytes = await _othersProfileService.getCachedProfilePicture(userId);
      if (profileBytes != null) {
        _profilePictureCache[userId] = profileBytes;
        return profileBytes;
      }
    }
    
    return null;
  }
  
  /// Get group avatar
  Future<Uint8List?> getGroupAvatar(String roomId) async {
    // Check memory cache first
    if (_groupAvatarCache.containsKey(roomId)) {
      return _groupAvatarCache[roomId];
    }
    
    // Load from disk cache
    final avatarBytes = await _othersProfileService.getCachedGroupAvatar(roomId);
    if (avatarBytes != null) {
      _groupAvatarCache[roomId] = avatarBytes;
      return avatarBytes;
    }
    
    return null;
  }
  
  /// Notify that a user profile has been updated
  void notifyProfileUpdated(String userId) {
    // Clear memory cache for this user
    _profilePictureCache.remove(userId);
    _updatedProfiles.add(userId);
    
    // Increment version to ensure widgets detect the change
    _profileVersions[userId] = (_profileVersions[userId] ?? 0) + 1;
    
    notifyListeners();
  }
  
  /// Notify that a group avatar has been updated
  void notifyGroupAvatarUpdated(String roomId) {
    // Clear memory cache for this group
    _groupAvatarCache.remove(roomId);
    _updatedGroups.add(roomId);
    
    // Increment version to ensure widgets detect the change
    _groupVersions[roomId] = (_groupVersions[roomId] ?? 0) + 1;
    
    notifyListeners();
  }
  
  /// Check if a profile was updated and clear the flag
  bool wasProfileUpdated(String userId) {
    return _updatedProfiles.remove(userId);
  }
  
  /// Check if a group avatar was updated and clear the flag
  bool wasGroupAvatarUpdated(String roomId) {
    return _updatedGroups.remove(roomId);
  }
  
  /// Get the current version of a profile (for change detection)
  int getProfileVersion(String userId) {
    return _profileVersions[userId] ?? 0;
  }
  
  /// Get the current version of a group avatar (for change detection)
  int getGroupAvatarVersion(String roomId) {
    return _groupVersions[roomId] ?? 0;
  }
  
  /// Clear cache for a specific user
  void clearUserCache(String userId) {
    _profilePictureCache.remove(userId);
    _updatedProfiles.add(userId);
    notifyListeners();
  }
  
  /// Clear cache for a specific group
  void clearGroupCache(String roomId) {
    _groupAvatarCache.remove(roomId);
    _updatedGroups.add(roomId);
    notifyListeners();
  }
  
  /// Clear all caches
  void clearCache() {
    _profilePictureCache.clear();
    _groupAvatarCache.clear();
    notifyListeners();
  }
}