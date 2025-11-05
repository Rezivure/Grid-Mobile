import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'package:random_avatar/random_avatar.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../utilities/utils.dart';
import '../services/avatar_cache_service.dart';

class UserAvatar extends StatefulWidget {
  final String userId;
  final double size;

  const UserAvatar({
    Key? key,
    required this.userId,
    this.size = 40,
  }) : super(key: key);

  @override
  _UserAvatarState createState() => _UserAvatarState();
  
  // Static notifier for cache invalidation
  static final _cacheInvalidationNotifier = ValueNotifier<String?>(null);
  
  // Static method to clear cache for a specific user
  static Future<void> clearCache(String userId) async {
    await _UserAvatarState._cacheService.remove(userId);
    // Notify all listening widgets
    _cacheInvalidationNotifier.value = userId;
  }
  
  // Static method to clear all cache
  static Future<void> clearAllCache() async {
    await _UserAvatarState._cacheService.clear();
    _cacheInvalidationNotifier.value = '*'; // Special value to indicate all cache cleared
  }
  
  // Static method to notify widgets that an avatar has been updated
  static void notifyAvatarUpdated(String userId) {
    _cacheInvalidationNotifier.value = userId;
  }
  
  // Expose the notifier for external listeners
  static ValueNotifier<String?> get avatarUpdateNotifier => _cacheInvalidationNotifier;
}

class _UserAvatarState extends State<UserAvatar> {
  static final AvatarCacheService _cacheService = AvatarCacheService();
  static bool _cacheInitialized = false;
  Uint8List? _avatarBytes;
  bool _isLoading = true;
  String? _loadedUserId;
  bool _hasCheckedCache = false;

  @override
  void initState() {
    super.initState();
    
    // Listen for cache invalidation
    UserAvatar._cacheInvalidationNotifier.addListener(_onCacheInvalidated);
    
    _initializeAndLoad();
  }
  
  Future<void> _initializeAndLoad() async {
    // Initialize cache on first use
    if (!_cacheInitialized) {
      _cacheInitialized = true;
      await _cacheService.initialize();
    }
    
    // Check persistent cache first - this survives hot reloads
    final cachedAvatar = _cacheService.get(widget.userId);
    if (cachedAvatar != null) {
      if (mounted) {
        setState(() {
          _avatarBytes = cachedAvatar;
          _loadedUserId = widget.userId;
          _isLoading = false;
          _hasCheckedCache = true;
        });
      }
      return;
    }
    
    // Mark that we've checked the cache
    if (mounted) {
      setState(() {
        _hasCheckedCache = true;
      });
    }
    
    // If not in cache, load it
    _loadUserAvatar();
  }
  
  @override
  void dispose() {
    UserAvatar._cacheInvalidationNotifier.removeListener(_onCacheInvalidated);
    super.dispose();
  }
  
  void _onCacheInvalidated() {
    final invalidatedUserId = UserAvatar._cacheInvalidationNotifier.value;
    if (invalidatedUserId == widget.userId || invalidatedUserId == '*') {
      // For avatar updates, always reload from secure storage
      // This ensures we get the latest avatar even if cache timing is off
      if (invalidatedUserId == widget.userId && invalidatedUserId != '*') {
        // Don't clear current avatar, just reload with force flag
        _loadUserAvatar(forceReload: true);
      } else {
        // For cache clear ('*'), do full reload
        _loadedUserId = null;
        _avatarBytes = null;
        _loadUserAvatar();
      }
    }
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload avatar if userId changed
    if (oldWidget.userId != widget.userId) {
      _loadedUserId = null;
      _avatarBytes = null;
      _loadUserAvatar();
    }
  }

  Future<void> _loadUserAvatar({bool forceReload = false}) async {
    // Don't reload if we already have the avatar bytes for this user (unless forced)
    if (!forceReload && _loadedUserId == widget.userId && _avatarBytes != null) return;
    
    // Also check if we're already loading to prevent duplicate requests
    if (_isLoading && _loadedUserId == widget.userId) return;
    
    _loadedUserId = widget.userId;

    // Check persistent cache first
    final cachedAvatar = _cacheService.get(widget.userId);
    if (cachedAvatar != null) {
      if (mounted) {
        setState(() {
          _avatarBytes = cachedAvatar;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        // Don't clear existing avatar - keep showing it while loading the new one
      });
    }

    try {
      const secureStorage = FlutterSecureStorage();
      final prefs = await SharedPreferences.getInstance();
      
      // Check if it's a Matrix avatar or encrypted avatar
      // For the current user, check without userId suffix
      final client = Provider.of<Client>(context, listen: false);
      final isCurrentUser = widget.userId == client.userID;
      final isMatrixAvatar = isCurrentUser 
          ? (prefs.getBool('avatar_is_matrix') ?? false)
          : (prefs.getBool('avatar_is_matrix_${widget.userId}') ?? false);
      
      // Check secure storage for avatar data
      String? avatarDataStr;
      try {
        avatarDataStr = await secureStorage.read(key: 'avatar_${widget.userId}');
      } catch (e) {
        print('[UserAvatar] Secure storage failed for ${widget.userId}, using fallback');
        // Try SharedPreferences fallback
        final fallbackStr = prefs.getString('avatar_fallback_${widget.userId}');
        if (fallbackStr != null) {
          avatarDataStr = fallbackStr;
        }
      }
      
      if (avatarDataStr != null) {
        final avatarData = json.decode(avatarDataStr);
        final uri = avatarData['uri'];
        final keyBase64 = avatarData['key'];
        final ivBase64 = avatarData['iv'];
        
        if (uri != null && keyBase64 != null && ivBase64 != null) {
          if (isMatrixAvatar) {
            // Download from Matrix
            final client = Provider.of<Client>(context, listen: false);
            final mxcUri = Uri.parse(uri);
            final serverName = mxcUri.host;
            final mediaId = mxcUri.path.substring(1);
            
            final file = await client.getContent(serverName, mediaId);
            
            // Decrypt
            final key = encrypt.Key.fromBase64(keyBase64);
            final iv = encrypt.IV.fromBase64(ivBase64);
            final encrypter = encrypt.Encrypter(encrypt.AES(key));
            final encrypted = encrypt.Encrypted(file.data);
            final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
            
            final avatarBytes = Uint8List.fromList(decrypted);
            await _cacheService.put(widget.userId, avatarBytes);
            
            if (mounted) {
              setState(() {
                _avatarBytes = avatarBytes;
                _isLoading = false;
              });
            }
          } else {
            // Download from R2
            final response = await http.get(Uri.parse(uri));
            
            if (response.statusCode == 200) {
              // Decrypt
              final key = encrypt.Key.fromBase64(keyBase64);
              final iv = encrypt.IV.fromBase64(ivBase64);
              final encrypter = encrypt.Encrypter(encrypt.AES(key));
              final encrypted = encrypt.Encrypted(response.bodyBytes);
              final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
              
              final avatarBytes = Uint8List.fromList(decrypted);
              await _cacheService.put(widget.userId, avatarBytes);
              print('[UserAvatar] Loaded avatar for ${widget.userId} (${avatarBytes.length} bytes)');
              
              if (mounted) {
                setState(() {
                  _avatarBytes = avatarBytes;
                  _isLoading = false;
                });
              }
            } else {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Add RepaintBoundary to isolate repaints
    return RepaintBoundary(
      child: _buildAvatar(context),
    );
  }
  
  Widget _buildAvatar(BuildContext context) {
    // If we have avatar bytes, show them immediately
    if (_avatarBytes != null) {
      return ClipOval(
        child: Image.memory(
          _avatarBytes!,
          fit: BoxFit.cover,
          width: widget.size,
          height: widget.size,
          gaplessPlayback: true, // Prevent flicker when updating
        ),
      );
    }

    // Only show loading if we haven't checked cache yet
    if (_isLoading && !_hasCheckedCache) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: SizedBox(
            width: widget.size * 0.4,
            height: widget.size * 0.4,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary.withOpacity(0.6),
              ),
            ),
          ),
        ),
      );
    }

    // Fallback to random avatar only after we've checked for a profile pic
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RandomAvatar(
        localpart(widget.userId),
        height: widget.size,
        width: widget.size,
      ),
    );
  }
}