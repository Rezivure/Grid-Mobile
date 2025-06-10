import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/services/profile_picture_service.dart';
import 'package:grid_frontend/utilities/profile_picture_encryption.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:grid_frontend/providers/profile_picture_provider.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';

class OthersProfileService {
  static const String PROFILES_METADATA_KEY = 'others_profiles_metadata';
  static const String CACHE_DIR = 'others_profile_pictures';
  
  final ProfilePictureService _profilePictureService = ProfilePictureService();
  ProfilePictureProvider? _profilePictureProvider;
  ContactsBloc? _contactsBloc;
  
  void setProfilePictureProvider(ProfilePictureProvider provider) {
    _profilePictureProvider = provider;
  }
  
  void setContactsBloc(ContactsBloc bloc) {
    _contactsBloc = bloc;
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
    final prefs = await SharedPreferences.getInstance();
    final allMetadata = prefs.getString(PROFILES_METADATA_KEY);
    
    if (allMetadata != null) {
      final metadata = json.decode(allMetadata) as Map<String, dynamic>;
      return metadata[userId] as Map<String, dynamic>?;
    }
    return null;
  }
  
  /// Clear cache for a specific user
  Future<void> clearUserProfile(String userId) async {
    try {
      // Remove cached image
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/${_sanitizeUserId(userId)}.jpg');
      if (await file.exists()) {
        await file.delete();
      }
      
      // Remove metadata
      final prefs = await SharedPreferences.getInstance();
      final allMetadata = prefs.getString(PROFILES_METADATA_KEY);
      
      if (allMetadata != null) {
        final metadata = json.decode(allMetadata) as Map<String, dynamic>;
        metadata.remove(userId);
        await prefs.setString(PROFILES_METADATA_KEY, json.encode(metadata));
      }
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PROFILES_METADATA_KEY);
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
    final prefs = await SharedPreferences.getInstance();
    final allMetadataStr = prefs.getString(PROFILES_METADATA_KEY);
    
    final allMetadata = allMetadataStr != null 
        ? json.decode(allMetadataStr) as Map<String, dynamic>
        : <String, dynamic>{};
    
    allMetadata[userId] = metadata;
    await prefs.setString(PROFILES_METADATA_KEY, json.encode(allMetadata));
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
}