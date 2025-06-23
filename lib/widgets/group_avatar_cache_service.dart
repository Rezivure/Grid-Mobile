import 'dart:typed_data';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A persistent group avatar cache service that survives hot reloads
class GroupAvatarCacheService {
  static final GroupAvatarCacheService _instance = GroupAvatarCacheService._internal();
  factory GroupAvatarCacheService() => _instance;
  GroupAvatarCacheService._internal();
  
  static const String _cacheKeyPrefix = 'group_avatar_cache_';
  static const String _cacheIndexKey = 'group_avatar_cache_index';
  static const int _maxCacheSize = 30; // Maximum number of group avatars to cache
  
  final Map<String, Uint8List> _memoryCache = {};
  bool _isInitialized = false;
  
  /// Initialize the cache by loading from persistent storage
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheIndex = prefs.getStringList(_cacheIndexKey) ?? [];
      
      // Load each cached avatar
      for (final roomId in cacheIndex) {
        final base64Data = prefs.getString('$_cacheKeyPrefix$roomId');
        if (base64Data != null) {
          try {
            _memoryCache[roomId] = base64Decode(base64Data);
          } catch (e) {
            print('[GroupAvatarCache] Error decoding cached avatar for $roomId: $e');
          }
        }
      }
      
      _isInitialized = true;
      print('[GroupAvatarCache] Loaded ${_memoryCache.length} group avatars from persistent cache');
    } catch (e) {
      print('[GroupAvatarCache] Error initializing cache: $e');
      _isInitialized = true; // Mark as initialized even on error
    }
  }
  
  /// Get avatar from cache
  Uint8List? get(String roomId) {
    return _memoryCache[roomId];
  }
  
  /// Store avatar in cache (both memory and persistent)
  Future<void> put(String roomId, Uint8List avatarBytes) async {
    _memoryCache[roomId] = avatarBytes;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Update cache index
      final cacheIndex = prefs.getStringList(_cacheIndexKey) ?? [];
      if (!cacheIndex.contains(roomId)) {
        cacheIndex.add(roomId);
        
        // Enforce cache size limit (remove oldest if needed)
        if (cacheIndex.length > _maxCacheSize) {
          final toRemove = cacheIndex.removeAt(0);
          _memoryCache.remove(toRemove);
          await prefs.remove('$_cacheKeyPrefix$toRemove');
        }
        
        await prefs.setStringList(_cacheIndexKey, cacheIndex);
      }
      
      // Store avatar data
      await prefs.setString('$_cacheKeyPrefix$roomId', base64Encode(avatarBytes));
    } catch (e) {
      print('[GroupAvatarCache] Error persisting avatar for $roomId: $e');
    }
  }
  
  /// Remove specific avatar from cache
  Future<void> remove(String roomId) async {
    _memoryCache.remove(roomId);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cacheKeyPrefix$roomId');
      
      final cacheIndex = prefs.getStringList(_cacheIndexKey) ?? [];
      cacheIndex.remove(roomId);
      await prefs.setStringList(_cacheIndexKey, cacheIndex);
    } catch (e) {
      print('[GroupAvatarCache] Error removing avatar for $roomId: $e');
    }
  }
  
  /// Clear all cached avatars
  Future<void> clear() async {
    _memoryCache.clear();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheIndex = prefs.getStringList(_cacheIndexKey) ?? [];
      
      // Remove all cached avatars
      for (final roomId in cacheIndex) {
        await prefs.remove('$_cacheKeyPrefix$roomId');
      }
      
      await prefs.remove(_cacheIndexKey);
    } catch (e) {
      print('[GroupAvatarCache] Error clearing cache: $e');
    }
  }
  
  /// Check if cache contains avatar for room
  bool contains(String roomId) {
    return _memoryCache.containsKey(roomId);
  }
  
  /// Get all cached room IDs
  List<String> getCachedRoomIds() {
    return _memoryCache.keys.toList();
  }
}