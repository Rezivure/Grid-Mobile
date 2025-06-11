import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:grid_frontend/services/others_profile_service.dart';
import 'package:grid_frontend/services/profile_picture_service.dart';
import 'package:matrix/matrix.dart';

class ProfilePictureProvider with ChangeNotifier {
  final OthersProfileService _othersProfileService = OthersProfileService();
  final ProfilePictureService _profilePictureService = ProfilePictureService();
  final Map<String, Uint8List?> _profilePictureCache = {};
  final Set<String> _updatedProfiles = {};
  final Map<String, int> _profileVersions = {};
  Client? _client;
  
  void setClient(Client client) {
    _client = client;
  }
  
  /// Get profile picture for a user
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
  
  /// Notify that a profile has been updated
  void notifyProfileUpdated(String userId) {
    print('ProfilePictureProvider.notifyProfileUpdated: Updating $userId');
    // Clear memory cache for this user
    _profilePictureCache.remove(userId);
    _updatedProfiles.add(userId);
    
    // Increment version to ensure widgets detect the change
    _profileVersions[userId] = (_profileVersions[userId] ?? 0) + 1;
    print('ProfilePictureProvider: Version for $userId is now ${_profileVersions[userId]}');
    
    notifyListeners();
  }
  
  /// Check if a profile was updated and clear the flag
  bool wasProfileUpdated(String userId) {
    return _updatedProfiles.remove(userId);
  }
  
  /// Get the current version of a profile (for change detection)
  int getProfileVersion(String userId) {
    return _profileVersions[userId] ?? 0;
  }
  
  /// Clear cache for a specific user
  void clearUserCache(String userId) {
    _profilePictureCache.remove(userId);
    _updatedProfiles.add(userId);
    notifyListeners();
  }
  
  /// Clear all caches
  void clearCache() {
    _profilePictureCache.clear();
    notifyListeners();
  }
}