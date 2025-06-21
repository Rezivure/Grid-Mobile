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
  static void clearCache(String userId) {
    _UserAvatarState._avatarCache.remove(userId);
    // Notify all listening widgets
    _cacheInvalidationNotifier.value = userId;
  }
  
  // Static method to clear all cache
  static void clearAllCache() {
    _UserAvatarState._avatarCache.clear();
    _cacheInvalidationNotifier.value = '*'; // Special value to indicate all cache cleared
  }
}

class _UserAvatarState extends State<UserAvatar> {
  static final Map<String, Uint8List> _avatarCache = {};
  Uint8List? _avatarBytes;
  bool _isLoading = false;
  String? _loadedUserId;

  @override
  void initState() {
    super.initState();
    _loadUserAvatar();
    
    // Listen for cache invalidation
    UserAvatar._cacheInvalidationNotifier.addListener(_onCacheInvalidated);
  }
  
  @override
  void dispose() {
    UserAvatar._cacheInvalidationNotifier.removeListener(_onCacheInvalidated);
    super.dispose();
  }
  
  void _onCacheInvalidated() {
    final invalidatedUserId = UserAvatar._cacheInvalidationNotifier.value;
    if (invalidatedUserId == widget.userId || invalidatedUserId == '*') {
      // Force reload if this user's cache was invalidated
      _loadedUserId = null;
      _avatarBytes = null;
      _loadUserAvatar();
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

  Future<void> _loadUserAvatar() async {
    // Don't reload if we already loaded this user's avatar
    if (_loadedUserId == widget.userId && _avatarBytes != null) return;
    
    _loadedUserId = widget.userId;

    // Check static cache first
    if (_avatarCache.containsKey(widget.userId)) {
      if (mounted) {
        setState(() {
          _avatarBytes = _avatarCache[widget.userId];
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _avatarBytes = null; // Clear any previous avatar
      });
    }

    try {
      final secureStorage = FlutterSecureStorage();
      final prefs = await SharedPreferences.getInstance();
      
      // Check if it's a Matrix avatar or encrypted avatar
      // For the current user, check without userId suffix
      final client = Provider.of<Client>(context, listen: false);
      final isCurrentUser = widget.userId == client.userID;
      final isMatrixAvatar = isCurrentUser 
          ? (prefs.getBool('avatar_is_matrix') ?? false)
          : (prefs.getBool('avatar_is_matrix_${widget.userId}') ?? false);
      
      // Check secure storage for avatar data
      final avatarDataStr = await secureStorage.read(key: 'avatar_${widget.userId}');
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
            final encrypted = encrypt.Encrypted(Uint8List.fromList(file.data));
            final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
            
            final avatarBytes = Uint8List.fromList(decrypted);
            _avatarCache[widget.userId] = avatarBytes;
            
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
              _avatarCache[widget.userId] = avatarBytes;
              
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
      print('[User Avatar] Error loading avatar for ${widget.userId}: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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

    if (_avatarBytes != null) {
      return ClipOval(
        child: Image.memory(
          _avatarBytes!,
          fit: BoxFit.cover,
          width: widget.size,
          height: widget.size,
        ),
      );
    }

    // Fallback to random avatar
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