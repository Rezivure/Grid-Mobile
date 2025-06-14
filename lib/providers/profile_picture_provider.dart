import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:grid_frontend/services/others_profile_service.dart';
import 'package:grid_frontend/services/profile_picture_service.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;

class ProfilePictureProvider with ChangeNotifier {
  final OthersProfileService _othersProfileService = OthersProfileService();
  final ProfilePictureService _profilePictureService = ProfilePictureService();
  final Map<String, Uint8List?> _profilePictureCache = {};
  final Map<String, Uint8List?> _groupAvatarCache = {};
  final Set<String> _updatedProfiles = {};
  final Set<String> _updatedGroups = {};
  final Map<String, int> _profileVersions = {};
  final Map<String, int> _groupVersions = {};
  final Map<String, Uri?> _lastKnownAvatarUrls = {};
  final Map<String, DateTime> _lastGroupUpdateTime = {};
  Client? _client;
  Timer? _avatarCheckTimer;
  Timer? _notifyTimer;
  bool _pendingNotify = false;
  
  void setClient(Client client) {
    _client = client;
    _startAvatarChangeDetection();
  }
  
  void _startAvatarChangeDetection() {
    if (_client == null) {
      print('[ProfilePictureProvider] Cannot start avatar detection - client is null');
      return;
    }
    
    final homeserver = _client!.homeserver.toString();
    final isCustom = utils.isCustomHomeserver(homeserver);
    
    print('[ProfilePictureProvider] Starting avatar detection - homeserver: $homeserver, isCustom: $isCustom');
    
    // Only check for avatar changes on custom homeservers
    if (isCustom) {
      // Check every 30 seconds for avatar changes
      _avatarCheckTimer?.cancel();
      _avatarCheckTimer = Timer.periodic(Duration(seconds: 30), (_) {
        _checkForAvatarChanges();
      });
      print('[ProfilePictureProvider] Avatar change detection timer started');
    } else {
      print('[ProfilePictureProvider] Not a custom homeserver, avatar detection not started');
    }
  }
  
  Future<void> _checkForAvatarChanges() async {
    if (_client == null) return;
    
    print('[ProfilePictureProvider] Checking for avatar changes...');
    
    // Get all cached user IDs
    final cachedUserIds = {..._profilePictureCache.keys, ..._lastKnownAvatarUrls.keys};
    print('[ProfilePictureProvider] Checking ${cachedUserIds.length} users for avatar changes');
    
    for (final userId in cachedUserIds) {
      if (userId.startsWith('@')) {  // Only check user IDs, not room IDs
        try {
          final currentAvatarUrl = await _client!.getAvatarUrl(userId);
          final lastKnownUrl = _lastKnownAvatarUrls[userId];
          
          if (currentAvatarUrl != lastKnownUrl) {
            // Avatar has changed
            print('[ProfilePictureProvider] Avatar changed for $userId');
            _lastKnownAvatarUrls[userId] = currentAvatarUrl;
            _profilePictureCache.remove(userId);
            notifyProfileUpdated(userId);
          }
        } catch (e) {
          // Ignore errors for individual users
          print('[ProfilePictureProvider] Error checking avatar for $userId: $e');
        }
      }
    }
  }
  
  @override
  void dispose() {
    _avatarCheckTimer?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
  
  void _throttledNotify() {
    if (_pendingNotify) return;
    
    _pendingNotify = true;
    _notifyTimer?.cancel();
    _notifyTimer = Timer(Duration(milliseconds: 100), () {
      _pendingNotify = false;
      notifyListeners();
    });
  }
  
  /// Get profile picture for a user or group
  Future<Uint8List?> getProfilePicture(String userId) async {
    // Check memory cache first
    if (_profilePictureCache.containsKey(userId)) {
      return _profilePictureCache[userId];
    }
    
    // Check if this is the current user
    if (_client != null && userId == _client!.userID) {
      // Check if custom homeserver
      final homeserver = _client!.homeserver.toString();
      final isCustom = utils.isCustomHomeserver(homeserver);
      
      if (isCustom) {
        // For custom homeservers, try Matrix avatar
        try {
          final avatarUrl = await _client!.getAvatarUrl(userId);
          // Store the avatar URL for change detection
          _lastKnownAvatarUrls[userId] = avatarUrl;
          
          if (avatarUrl != null) {
            // Build the download URL manually
            final homeserverUrl = _client!.homeserver;
            final mxcParts = avatarUrl.toString().replaceFirst('mxc://', '').split('/');
            if (mxcParts.length == 2) {
              final serverName = mxcParts[0];
              final mediaId = mxcParts[1];
              final downloadUri = Uri.parse('$homeserverUrl/_matrix/media/v3/download/$serverName/$mediaId');
              
              final response = await _client!.httpClient.get(downloadUri);
              if (response.statusCode == 200) {
                final avatarBytes = response.bodyBytes;
                _profilePictureCache[userId] = avatarBytes;
                return avatarBytes;
              }
            }
          }
        } catch (e) {
          print('Error downloading Matrix avatar: $e');
        }
      } else {
        // Load current user's profile picture from ProfilePictureService
        final profileBytes = await _profilePictureService.getLocalProfilePicture();
        if (profileBytes != null) {
          _profilePictureCache[userId] = profileBytes;
          return profileBytes;
        }
      }
    } else {
      // For other users, check if custom homeserver
      final homeserver = _client?.homeserver.toString() ?? '';
      final isCustom = utils.isCustomHomeserver(homeserver);
      
      if (isCustom) {
        // Try Matrix avatar for other users on custom homeservers
        try {
          final avatarUrl = await _client!.getAvatarUrl(userId);
          // Store the avatar URL for change detection
          _lastKnownAvatarUrls[userId] = avatarUrl;
          print('[ProfilePictureProvider] Stored avatar URL for $userId: $avatarUrl');
          
          if (avatarUrl != null) {
            // Build the download URL manually
            final homeserverUrl = _client!.homeserver;
            final mxcParts = avatarUrl.toString().replaceFirst('mxc://', '').split('/');
            if (mxcParts.length == 2) {
              final serverName = mxcParts[0];
              final mediaId = mxcParts[1];
              final downloadUri = Uri.parse('$homeserverUrl/_matrix/media/v3/download/$serverName/$mediaId');
              
              final response = await _client!.httpClient.get(downloadUri);
              if (response.statusCode == 200) {
                final avatarBytes = response.bodyBytes;
                _profilePictureCache[userId] = avatarBytes;
                return avatarBytes;
              }
            }
          }
        } catch (e) {
          print('Error downloading Matrix avatar for $userId: $e');
        }
      } else {
        // Load from disk cache for other users
        final profileBytes = await _othersProfileService.getCachedProfilePicture(userId);
        if (profileBytes != null) {
          _profilePictureCache[userId] = profileBytes;
          return profileBytes;
        }
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
    
    _throttledNotify();
  }
  
  /// Notify that a group avatar has been updated
  void notifyGroupAvatarUpdated(String roomId) {
    // Prevent rapid-fire updates for the same room
    final now = DateTime.now();
    final lastUpdate = _lastGroupUpdateTime[roomId];
    if (lastUpdate != null && now.difference(lastUpdate).inMilliseconds < 500) {
      print('[ProfilePictureProvider] Skipping rapid update for room $roomId');
      return;
    }
    _lastGroupUpdateTime[roomId] = now;
    
    // Clear memory cache for this group
    _groupAvatarCache.remove(roomId);
    _updatedGroups.add(roomId);
    
    // Increment version to ensure widgets detect the change
    _groupVersions[roomId] = (_groupVersions[roomId] ?? 0) + 1;
    
    // Log version increment for debugging
    print('[ProfilePictureProvider] Group avatar version for $roomId: ${_groupVersions[roomId]}');
    
    // Notify immediately for user-initiated updates
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
    _throttledNotify();
  }
  
  /// Clear cache for a specific group
  void clearGroupCache(String roomId) {
    _groupAvatarCache.remove(roomId);
    _updatedGroups.add(roomId);
    _throttledNotify();
  }
  
  /// Clear all caches
  void clearCache() {
    _profilePictureCache.clear();
    _groupAvatarCache.clear();
    _throttledNotify();
  }
  
  /// Manually trigger avatar change check (for testing/debugging)
  Future<void> manualCheckForAvatarChanges() async {
    print('[ProfilePictureProvider] Manual avatar check triggered');
    await _checkForAvatarChanges();
  }
}