import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'triangle_avatars.dart';

class GroupAvatar extends StatefulWidget {
  final String roomId;
  final List<String> memberIds;
  final double size;

  const GroupAvatar({
    Key? key,
    required this.roomId,
    required this.memberIds,
    this.size = 72,
  }) : super(key: key);

  @override
  _GroupAvatarState createState() => _GroupAvatarState();
}

class _GroupAvatarState extends State<GroupAvatar> {
  static final Map<String, Uint8List> _groupAvatarCache = {};
  Uint8List? _avatarBytes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadGroupAvatar();
  }

  Future<void> _loadGroupAvatar() async {
    // Check static cache first
    if (_groupAvatarCache.containsKey(widget.roomId)) {
      setState(() {
        _avatarBytes = _groupAvatarCache[widget.roomId];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final secureStorage = FlutterSecureStorage();
      final prefs = await SharedPreferences.getInstance();
      
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
            _groupAvatarCache[widget.roomId] = avatarBytes;
            
            setState(() {
              _avatarBytes = avatarBytes;
              _isLoading = false;
            });
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
              _groupAvatarCache[widget.roomId] = avatarBytes;
              
              setState(() {
                _avatarBytes = avatarBytes;
                _isLoading = false;
              });
            } else {
              setState(() {
                _isLoading = false;
              });
            }
          }
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[Group Avatar] Error loading avatar: $e');
      setState(() {
        _isLoading = false;
      });
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

    // Fallback to triangle avatars
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: TriangleAvatars(userIds: widget.memberIds),
    );
  }
}