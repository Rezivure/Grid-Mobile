import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grid_frontend/services/profile_picture_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:grid_frontend/providers/profile_picture_provider.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';
import 'package:grid_frontend/services/logger_service.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';

class OthersProfileService {
  static const String PROFILES_METADATA_KEY = 'others_profiles_metadata';
  static const String GROUP_AVATARS_METADATA_KEY = 'group_avatars_metadata';
  static const String CACHE_DIR = 'others_profile_pictures';
  static const String GROUP_CACHE_DIR = 'group_avatars';
  
  final ProfilePictureService _profilePictureService = ProfilePictureService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  ProfilePictureProvider? _profilePictureProvider;
  ContactsBloc? _contactsBloc;
  GroupsBloc? _groupsBloc;
  
  void setProfilePictureProvider(ProfilePictureProvider provider) {
    _profilePictureProvider = provider;
  }
  
  void setContactsBloc(ContactsBloc bloc) {
    _contactsBloc = bloc;
  }
  
  void setGroupsBloc(GroupsBloc bloc) {
    _groupsBloc = bloc;
  }
  
  /// Process a profile announcement message
  Future<void> processProfileAnnouncement(String userId, Map<String, dynamic> profileData) async {
    try {
      final url = profileData['url'] as String?;
      final key = profileData['key'] as String?;
      final iv = profileData['iv'] as String?;
      final updatedAt = profileData['updated_at'] as String?;
      
      if (url == null || key == null || iv == null) {
        print('Invalid profile announcement data for $userId');
        return;
      }
      
      // Check if we already have this exact profile cached
      final existingProfile = await getProfileMetadata(userId);
      if (existingProfile != null && 
          existingProfile['url'] == url &&
          existingProfile['updated_at'] == updatedAt) {
        // Already have this exact profile
        return;
      }
      
      // Download and cache the new profile
      final profileBytes = await _profilePictureService.downloadProfilePicture(url, key, iv);
      if (profileBytes != null) {
        // Cache the decrypted image
        await _cacheProfilePicture(userId, profileBytes);
        
        // Save metadata
        await _saveProfileMetadata(userId, {
          'url': url,
          'key': key,
          'iv': iv,
          'updated_at': updatedAt,
          'cached_at': DateTime.now().toIso8601String(),
        });
        
        // Notify provider to update UI
        _profilePictureProvider?.notifyProfileUpdated(userId);
        
        // Trigger contacts refresh to update the list
        _contactsBloc?.add(RefreshContacts());
        
        // Also trigger groups refresh to update member lists
        _groupsBloc?.add(RefreshGroups());
        
        print('Profile announcement processed successfully for $userId');
      } else {
        print('Profile announcement failed for $userId');
      }
    } catch (e) {
      print('Error processing profile announcement for $userId: $e');
    }
  }
  
  /// Get cached profile picture for a user
  Future<Uint8List?> getCachedProfilePicture(String userId) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/${_sanitizeUserId(userId)}.jpg');
      
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      
      // Try to download if we have metadata
      final metadata = await getProfileMetadata(userId);
      if (metadata != null) {
        final url = metadata['url'] as String?;
        final key = metadata['key'] as String?;
        final iv = metadata['iv'] as String?;
        
        if (url != null && key != null && iv != null) {
          final profileBytes = await _profilePictureService.downloadProfilePicture(url, key, iv);
          if (profileBytes != null) {
            await _cacheProfilePicture(userId, profileBytes);
            return profileBytes;
          }
        }
      }
    } catch (e) {
      print('Error getting cached profile for $userId: $e');
    }
    return null;
  }
  
  /// Get profile metadata for a user
  Future<Map<String, dynamic>?> getProfileMetadata(String userId) async {
    try {
      final allMetadata = await _secureStorage.read(key: PROFILES_METADATA_KEY);
      
      if (allMetadata != null) {
        final metadata = json.decode(allMetadata) as Map<String, dynamic>;
        return metadata[userId] as Map<String, dynamic>?;
      }
    } catch (e) {
      print('Error reading profile metadata: $e');
    }
    return null;
  }
  
  /// Clear cache for a specific user
  Future<void> clearUserProfile(String userId) async {
    try {
      print('OthersProfileService: Clearing profile for $userId');
      
      // Remove cached image
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/${_sanitizeUserId(userId)}.jpg');
      if (await file.exists()) {
        await file.delete();
        print('OthersProfileService: Deleted cached image file for $userId');
      } else {
        print('OthersProfileService: No cached image file found for $userId');
      }
      
      // Remove metadata
      final allMetadata = await _secureStorage.read(key: PROFILES_METADATA_KEY);
      
      if (allMetadata != null) {
        final metadata = json.decode(allMetadata) as Map<String, dynamic>;
        if (metadata.containsKey(userId)) {
          metadata.remove(userId);
          await _secureStorage.write(
            key: PROFILES_METADATA_KEY,
            value: json.encode(metadata)
          );
          print('OthersProfileService: Removed metadata for $userId');
        } else {
          print('OthersProfileService: No metadata found for $userId');
        }
      }
      
      // Also notify the provider to clear from memory cache
      _profilePictureProvider?.clearUserCache(userId);
      print('OthersProfileService: Profile cleared for $userId');
    } catch (e) {
      print('Error clearing profile for $userId: $e');
    }
  }
  
  /// Clear all cached profiles
  Future<void> clearAllProfiles() async {
    try {
      // Clear cache directory
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      
      // Clear metadata
      await _secureStorage.delete(key: PROFILES_METADATA_KEY);
    } catch (e) {
      print('Error clearing all profiles: $e');
    }
  }
  
  /// Cache a profile picture
  Future<void> _cacheProfilePicture(String userId, Uint8List imageBytes) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/${_sanitizeUserId(userId)}.jpg');
      await file.writeAsBytes(imageBytes);
    } catch (e) {
      print('Error caching profile picture: $e');
    }
  }
  
  /// Save profile metadata
  Future<void> _saveProfileMetadata(String userId, Map<String, dynamic> metadata) async {
    final allMetadataStr = await _secureStorage.read(key: PROFILES_METADATA_KEY);
    
    final allMetadata = allMetadataStr != null 
        ? json.decode(allMetadataStr) as Map<String, dynamic>
        : <String, dynamic>{};
    
    allMetadata[userId] = metadata;
    await _secureStorage.write(
      key: PROFILES_METADATA_KEY,
      value: json.encode(allMetadata)
    );
  }
  
  /// Get cache directory
  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/$CACHE_DIR');
    
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    
    return cacheDir;
  }
  
  /// Sanitize user ID for filename
  String _sanitizeUserId(String userId) {
    return userId.replaceAll('@', '').replaceAll(':', '_').replaceAll('.', '_');
  }
  
  // ======== GROUP AVATAR METHODS ========
  
  /// Process a group avatar announcement message
  Future<void> processGroupAvatarAnnouncement(String roomId, Map<String, dynamic> avatarData, {bool forceRefresh = false}) async {
    try {
      final url = avatarData['url'] as String?;
      final key = avatarData['key'] as String?;
      final iv = avatarData['iv'] as String?;
      final updatedAt = avatarData['updated_at'] as String?;
      
      if (url == null || key == null || iv == null) {
        print('Invalid group avatar announcement data for $roomId');
        return;
      }
      
      // Check if we already have this exact avatar cached
      final existingAvatar = await getGroupAvatarMetadata(roomId);
      if (!forceRefresh && existingAvatar != null && 
          existingAvatar['url'] == url &&
          existingAvatar['updated_at'] == updatedAt) {
        Logger.debug('OthersProfileService', 'Group avatar already cached, skipping', data: {'roomId': roomId});
        // Don't notify if already cached - this prevents infinite loops
        return;
      }
      
      // Download and cache the new avatar
      final avatarBytes = await _profilePictureService.downloadProfilePicture(url, key, iv);
      if (avatarBytes != null) {
        // Cache the decrypted image
        await _cacheGroupAvatar(roomId, avatarBytes);
        
        // Save metadata
        await _saveGroupAvatarMetadata(roomId, {
          'url': url,
          'key': key,
          'iv': iv,
          'updated_at': updatedAt,
          'cached_at': DateTime.now().toIso8601String(),
        });
        
        // Notify provider to update UI (using roomId as the identifier)
        _profilePictureProvider?.notifyGroupAvatarUpdated(roomId);
        
        // Trigger groups refresh to update the list
        _groupsBloc?.add(RefreshGroups());
        
        print('Group avatar announcement processed successfully for $roomId');
      } else {
        print('Group avatar announcement failed for $roomId');
      }
    } catch (e) {
      print('Error processing group avatar announcement for $roomId: $e');
    }
  }
  
  /// Get cached group avatar
  Future<Uint8List?> getCachedGroupAvatar(String roomId) async {
    try {
      final cacheDir = await _getGroupCacheDirectory();
      final file = File('${cacheDir.path}/${_sanitizeRoomId(roomId)}.jpg');
      
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      
      // Try to download if we have metadata
      final metadata = await getGroupAvatarMetadata(roomId);
      if (metadata != null) {
        final url = metadata['url'] as String?;
        final key = metadata['key'] as String?;
        final iv = metadata['iv'] as String?;
        
        if (url != null && key != null && iv != null) {
          final avatarBytes = await _profilePictureService.downloadProfilePicture(url, key, iv);
          if (avatarBytes != null) {
            await _cacheGroupAvatar(roomId, avatarBytes);
            return avatarBytes;
          }
        }
      }
    } catch (e) {
      print('Error getting cached group avatar for $roomId: $e');
    }
    return null;
  }
  
  /// Get group avatar metadata
  Future<Map<String, dynamic>?> getGroupAvatarMetadata(String roomId) async {
    try {
      final allMetadata = await _secureStorage.read(key: GROUP_AVATARS_METADATA_KEY);
      
      if (allMetadata != null) {
        final metadata = json.decode(allMetadata) as Map<String, dynamic>;
        return metadata[roomId] as Map<String, dynamic>?;
      }
    } catch (e) {
      print('Error reading group avatar metadata: $e');
    }
    return null;
  }
  
  /// Clear group avatar
  Future<void> clearGroupAvatar(String roomId) async {
    try {
      // Remove cached image
      final cacheDir = await _getGroupCacheDirectory();
      final file = File('${cacheDir.path}/${_sanitizeRoomId(roomId)}.jpg');
      if (await file.exists()) {
        await file.delete();
      }
      
      // Remove metadata
      final allMetadata = await _secureStorage.read(key: GROUP_AVATARS_METADATA_KEY);
      
      if (allMetadata != null) {
        final metadata = json.decode(allMetadata) as Map<String, dynamic>;
        metadata.remove(roomId);
        await _secureStorage.write(
          key: GROUP_AVATARS_METADATA_KEY, 
          value: json.encode(metadata)
        );
      }
      
      // Notify provider
      _profilePictureProvider?.clearGroupCache(roomId);
    } catch (e) {
      print('Error clearing group avatar for $roomId: $e');
    }
  }
  
  /// Cache a group avatar
  Future<void> _cacheGroupAvatar(String roomId, Uint8List imageBytes) async {
    try {
      final cacheDir = await _getGroupCacheDirectory();
      final file = File('${cacheDir.path}/${_sanitizeRoomId(roomId)}.jpg');
      await file.writeAsBytes(imageBytes);
    } catch (e) {
      print('Error caching group avatar: $e');
    }
  }
  
  /// Save group avatar metadata
  Future<void> _saveGroupAvatarMetadata(String roomId, Map<String, dynamic> metadata) async {
    final allMetadataStr = await _secureStorage.read(key: GROUP_AVATARS_METADATA_KEY);
    
    final allMetadata = allMetadataStr != null 
        ? json.decode(allMetadataStr) as Map<String, dynamic>
        : <String, dynamic>{};
    
    allMetadata[roomId] = metadata;
    await _secureStorage.write(
      key: GROUP_AVATARS_METADATA_KEY,
      value: json.encode(allMetadata)
    );
  }
  
  /// Get group cache directory
  Future<Directory> _getGroupCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/$GROUP_CACHE_DIR');
    
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    
    return cacheDir;
  }
  
  /// Sanitize room ID for filename
  String _sanitizeRoomId(String roomId) {
    return roomId.replaceAll('!', '').replaceAll(':', '_').replaceAll('.', '_');
  }
}