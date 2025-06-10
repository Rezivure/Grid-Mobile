import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:grid_frontend/services/others_profile_service.dart';

class ProfilePictureProvider with ChangeNotifier {
  final OthersProfileService _othersProfileService = OthersProfileService();
  final Map<String, Uint8List?> _profilePictureCache = {};
  final Set<String> _updatedProfiles = {};
  
  /// Get profile picture for a user
  Future<Uint8List?> getProfilePicture(String userId) async {
    // Check memory cache first
    if (_profilePictureCache.containsKey(userId)) {
      return _profilePictureCache[userId];
    }
    
    // Load from disk cache
    final profileBytes = await _othersProfileService.getCachedProfilePicture(userId);
    if (profileBytes != null) {
      _profilePictureCache[userId] = profileBytes;
      return profileBytes;
    }
    
    return null;
  }
  
  /// Notify that a profile has been updated
  void notifyProfileUpdated(String userId) {
    // Clear memory cache for this user
    _profilePictureCache.remove(userId);
    _updatedProfiles.add(userId);
    notifyListeners();
  }
  
  /// Check if a profile was updated and clear the flag
  bool wasProfileUpdated(String userId) {
    return _updatedProfiles.remove(userId);
  }
  
  /// Clear all caches
  void clearCache() {
    _profilePictureCache.clear();
    notifyListeners();
  }
}