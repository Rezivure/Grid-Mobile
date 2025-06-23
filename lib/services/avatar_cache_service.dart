import 'dart:typed_data';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A persistent avatar cache service that survives hot reloads
class AvatarCacheService {
  static final AvatarCacheService _instance = AvatarCacheService._internal();
  factory AvatarCacheService() => _instance;
  AvatarCacheService._internal();
  
  static const String _cacheKeyPrefix = 'avatar_cache_';
  static const String _cacheIndexKey = 'avatar_cache_index';
  static const int _maxCacheSize = 50; // Maximum number of avatars to cache
  
  final Map<String, Uint8List> _memoryCache = {};
  bool _isInitialized = false;
  
  /// Initialize the cache by loading from persistent storage
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheIndex = prefs.getStringList(_cacheIndexKey) ?? [];
      
      // Load each cached avatar
      for (final userId in cacheIndex) {
        final base64Data = prefs.getString('$_cacheKeyPrefix$userId');
        if (base64Data != null) {
          try {
            _memoryCache[userId] = base64Decode(base64Data);
          } catch (e) {
            print('[AvatarCache] Error decoding cached avatar for $userId: $e');
          }
        }
      }
      
      _isInitialized = true;
      print('[AvatarCache] Loaded ${_memoryCache.length} avatars from persistent cache');
    } catch (e) {
      print('[AvatarCache] Error initializing cache: $e');
      _isInitialized = true; // Mark as initialized even on error
    }
  }
  
  /// Get avatar from cache
  Uint8List? get(String userId) {
    return _memoryCache[userId];
  }
  
  /// Store avatar in cache (both memory and persistent)
  Future<void> put(String userId, Uint8List avatarBytes) async {
    _memoryCache[userId] = avatarBytes;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Update cache index
      final cacheIndex = prefs.getStringList(_cacheIndexKey) ?? [];
      if (!cacheIndex.contains(userId)) {
        cacheIndex.add(userId);
        
        // Enforce cache size limit (remove oldest if needed)
        if (cacheIndex.length > _maxCacheSize) {
          final toRemove = cacheIndex.removeAt(0);
          _memoryCache.remove(toRemove);
          await prefs.remove('$_cacheKeyPrefix$toRemove');
        }
        
        await prefs.setStringList(_cacheIndexKey, cacheIndex);
      }
      
      // Store avatar data
      await prefs.setString('$_cacheKeyPrefix$userId', base64Encode(avatarBytes));
    } catch (e) {
      print('[AvatarCache] Error persisting avatar for $userId: $e');
    }
  }
  
  /// Remove specific avatar from cache
  Future<void> remove(String userId) async {
    _memoryCache.remove(userId);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cacheKeyPrefix$userId');
      
      final cacheIndex = prefs.getStringList(_cacheIndexKey) ?? [];
      cacheIndex.remove(userId);
      await prefs.setStringList(_cacheIndexKey, cacheIndex);
    } catch (e) {
      print('[AvatarCache] Error removing avatar for $userId: $e');
    }
  }
  
  /// Clear all cached avatars
  Future<void> clear() async {
    _memoryCache.clear();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheIndex = prefs.getStringList(_cacheIndexKey) ?? [];
      
      // Remove all cached avatars
      for (final userId in cacheIndex) {
        await prefs.remove('$_cacheKeyPrefix$userId');
      }
      
      await prefs.remove(_cacheIndexKey);
    } catch (e) {
      print('[AvatarCache] Error clearing cache: $e');
    }
  }
  
  /// Check if cache contains avatar for user
  bool contains(String userId) {
    return _memoryCache.containsKey(userId);
  }
  
  /// Get all cached user IDs
  List<String> getCachedUserIds() {
    return _memoryCache.keys.toList();
  }
}