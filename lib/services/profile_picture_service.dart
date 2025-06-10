import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:grid_frontend/utilities/profile_picture_encryption.dart';

class ProfilePictureService {
  static const String PREF_PROFILE_PIC_METADATA = 'profile_pic_metadata';
  static const String CACHE_DIR = 'profile_pictures';
  
  final String _baseUrl = '${dotenv.env['GAUTH_URL']!}';
  
  /// Uploads an encrypted profile picture
  Future<Map<String, dynamic>> uploadProfilePicture(File imageFile, String jwtToken) async {
    try {
      // Generate encryption key and IV
      final encryptionKey = ProfilePictureEncryption.generateEncryptionKey();
      final iv = ProfilePictureEncryption.generateIV();
      
      // Encrypt the file
      final encryptedBytes = await ProfilePictureEncryption.encryptFile(
        imageFile, 
        encryptionKey, 
        iv
      );
      
      // Create multipart request
      final uri = Uri.parse('$_baseUrl/upload-profile-pic');
      final request = http.MultipartRequest('POST', uri);
      
      // Add authorization header
      request.headers['Authorization'] = 'Bearer $jwtToken';
      
      // Add encrypted file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          encryptedBytes,
          filename: 'profile.enc',
        ),
      );
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        // Create metadata
        final metadata = ProfilePictureEncryption.createMetadata(
          encryptionKey: encryptionKey,
          iv: iv,
          url: responseData['url'],
          filename: responseData['filename'],
        );
        
        // Save metadata locally
        await _saveMetadata(metadata);
        
        // Cache the encrypted file locally - extract just the filename
        final cacheFilename = responseData['filename'].toString().split('/').last;
        await _cacheEncryptedFile(encryptedBytes, cacheFilename);
        
        return metadata;
      } else {
        throw Exception('Failed to upload profile picture: ${response.body}');
      }
    } catch (e) {
      throw Exception('Profile picture upload failed: $e');
    }
  }
  
  /// Downloads and decrypts a profile picture
  Future<Uint8List?> downloadProfilePicture(String url, String encryptionKey, String iv) async {
    try {
      // Extract just the filename without path prefixes
      final urlParts = url.split('/');
      final filenameWithPath = urlParts.last; // e.g., "p/502d7bde1b8045b5ac3af4ee384adaa0.enc"
      final filename = filenameWithPath.split('/').last; // Just "502d7bde1b8045b5ac3af4ee384adaa0.enc"
      
      
      // Check cache first
      final cachedBytes = await _getCachedFile(filename);
      if (cachedBytes != null) {
        // Decrypt and return cached file
        return ProfilePictureEncryption.decryptBytes(cachedBytes, encryptionKey, iv);
      }
      
      // Download from server
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final encryptedBytes = response.bodyBytes;
        
        // Cache the encrypted file with just the filename
        await _cacheEncryptedFile(encryptedBytes, filename);
        
        // Decrypt and return
        return ProfilePictureEncryption.decryptBytes(encryptedBytes, encryptionKey, iv);
      } else {
        throw Exception('Failed to download profile picture');
      }
    } catch (e) {
      // Silent fail
      return null;
    }
  }
  
  /// Deletes a profile picture from the server
  Future<bool> deleteProfilePicture(String filename, String jwtToken) async {
    try {
      final uri = Uri.parse('$_baseUrl/delete-profile-pic');
      final response = await http.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({'filename': filename}),
      );
      
      if (response.statusCode == 200) {
        // Clear local metadata and cache
        await clearLocalProfilePicture();
        return true;
      } else {
        throw Exception('Failed to delete profile picture: ${response.body}');
      }
    } catch (e) {
      // Silent fail
      return false;
    }
  }
  
  /// Gets the current profile picture metadata
  Future<Map<String, dynamic>?> getProfilePictureMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final metadataString = prefs.getString(PREF_PROFILE_PIC_METADATA);
    
    if (metadataString != null) {
      return json.decode(metadataString);
    }
    return null;
  }
  
  /// Saves profile picture metadata
  Future<void> _saveMetadata(Map<String, dynamic> metadata) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREF_PROFILE_PIC_METADATA, json.encode(metadata));
  }
  
  /// Clears local profile picture data
  Future<void> clearLocalProfilePicture() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PREF_PROFILE_PIC_METADATA);
    
    // Clear cache directory
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (e) {
      // Silent fail
    }
  }
  
  /// Gets the cache directory for profile pictures
  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/$CACHE_DIR');
    
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    
    return cacheDir;
  }
  
  /// Caches an encrypted file
  Future<void> _cacheEncryptedFile(Uint8List bytes, String filename) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final filePath = '${cacheDir.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
    } catch (e) {
      // Silent fail for caching
    }
  }
  
  /// Gets a cached file
  Future<Uint8List?> _getCachedFile(String filename) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final file = File('${cacheDir.path}/$filename');
      
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      // Silent fail
    }
    return null;
  }
  
  /// Gets decrypted profile picture from local storage
  Future<Uint8List?> getLocalProfilePicture() async {
    try {
      final metadata = await getProfilePictureMetadata();
      if (metadata == null) return null;
      
      // Extract just the filename without path prefixes
      final filenameWithPath = metadata['filename']; // e.g., "p/502d7bde1b8045b5ac3af4ee384adaa0.enc"
      final filename = filenameWithPath.split('/').last; // Just "502d7bde1b8045b5ac3af4ee384adaa0.enc"
      final encryptionKey = metadata['key'];
      final iv = metadata['iv'];
      
      final cachedBytes = await _getCachedFile(filename);
      if (cachedBytes != null) {
        return ProfilePictureEncryption.decryptBytes(cachedBytes, encryptionKey, iv);
      }
      
      // If not cached, download it
      return await downloadProfilePicture(metadata['url'], encryptionKey, iv);
    } catch (e) {
      // Silent fail
      return null;
    }
  }
}