import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import '../utilities/utils.dart';
import '../blocs/avatar/avatar_bloc.dart';
import '../blocs/avatar/avatar_event.dart';
import '../blocs/avatar/avatar_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matrix/matrix.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'group_avatar_cache_service.dart';
import 'triangle_avatars.dart';

class GroupAvatarBloc extends StatefulWidget {
  final String roomId;
  final double size;
  final List<String>? memberIds;

  const GroupAvatarBloc({
    Key? key,
    required this.roomId,
    this.size = 40,
    this.memberIds,
  }) : super(key: key);

  @override
  _GroupAvatarBlocState createState() => _GroupAvatarBlocState();
}

class _GroupAvatarBlocState extends State<GroupAvatarBloc> {
  static final GroupAvatarCacheService _cacheService = GroupAvatarCacheService();
  static bool _cacheInitialized = false;
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  Uint8List? _avatarBytes;
  bool _isLoading = true;
  String? _loadedRoomId;
  bool _hasCheckedCache = false;

  @override
  void initState() {
    super.initState();
    _initializeAndLoad();
  }

  Future<void> _initializeAndLoad() async {
    // Initialize cache on first use
    if (!_cacheInitialized) {
      _cacheInitialized = true;
      await _cacheService.initialize();
    }
    
    // Check persistent cache first
    final cachedAvatar = _cacheService.get(widget.roomId);
    if (cachedAvatar != null) {
      if (mounted) {
        setState(() {
          _avatarBytes = cachedAvatar;
          _loadedRoomId = widget.roomId;
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
    _loadGroupAvatar();
  }

  @override
  void didUpdateWidget(GroupAvatarBloc oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload avatar if roomId changed
    if (oldWidget.roomId != widget.roomId) {
      _loadedRoomId = null;
      _avatarBytes = null;
      _loadGroupAvatar();
    }
  }

  Future<void> _loadGroupAvatar({bool forceReload = false}) async {
    // Don't reload if we already have the avatar bytes for this room (unless forced)
    if (!forceReload && _loadedRoomId == widget.roomId && _avatarBytes != null) return;
    
    // Also check if we're already loading to prevent duplicate requests
    if (_isLoading && _loadedRoomId == widget.roomId && !forceReload) return;
    
    _loadedRoomId = widget.roomId;

    // Check persistent cache first (unless force reloading)
    if (!forceReload) {
      final cachedAvatar = _cacheService.get(widget.roomId);
      if (cachedAvatar != null) {
        if (mounted) {
          setState(() {
            _avatarBytes = cachedAvatar;
            _isLoading = false;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final client = Provider.of<Client>(context, listen: false);
      
      // Check if it's a Matrix avatar or encrypted avatar
      final isMatrixAvatar = prefs.getBool('group_avatar_is_matrix_${widget.roomId}') ?? false;
      
      // Check secure storage for avatar data
      final avatarDataStr = await secureStorage.read(key: 'group_avatar_${widget.roomId}');
      if (avatarDataStr != null) {
        final avatarData = json.decode(avatarDataStr);
        final uri = avatarData['uri'];
        final keyBase64 = avatarData['key'];
        final ivBase64 = avatarData['iv'];
        
        if (uri != null && keyBase64 != null && ivBase64 != null) {
          if (isMatrixAvatar) {
            // Download from Matrix
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
            await _cacheService.put(widget.roomId, avatarBytes);
            
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
              await _cacheService.put(widget.roomId, avatarBytes);
              
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
      print('[Group Avatar] Error loading avatar for ${widget.roomId}: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AvatarBloc, AvatarState>(
      listenWhen: (previous, current) => previous.updateCounter != current.updateCounter,
      listener: (context, state) {
        // Force reload when avatar state updates
        _loadGroupAvatar(forceReload: true);
      },
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

    // Fallback to TriangleAvatars if memberIds provided, otherwise default group icon
    if (widget.memberIds != null && widget.memberIds!.isNotEmpty) {
      // TriangleAvatars has a fixed size of 60x60 (radius 30)
      // So we need to scale it to match the requested size
      final scale = widget.size / 60.0;
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Transform.scale(
          scale: scale,
          child: TriangleAvatars(
            userIds: widget.memberIds!,
          ),
        ),
      );
    }
    
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.group,
        size: widget.size * 0.6,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}