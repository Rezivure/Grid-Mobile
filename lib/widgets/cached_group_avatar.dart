import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:grid_frontend/providers/profile_picture_provider.dart';
import 'package:grid_frontend/services/others_profile_service.dart';
import 'package:grid_frontend/services/message_processor.dart';
import 'package:grid_frontend/widgets/triangle_avatars.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CachedGroupAvatar extends StatefulWidget {
  final String roomId;
  final List<String> memberIds;
  final double radius;
  final String? groupName;
  
  const CachedGroupAvatar({
    Key? key,
    required this.roomId,
    required this.memberIds,
    this.radius = 20,
    this.groupName,
  }) : super(key: key);

  @override
  _CachedGroupAvatarState createState() => _CachedGroupAvatarState();
}

class _CachedGroupAvatarState extends State<CachedGroupAvatar> {
  Uint8List? _avatarBytes;
  bool _isLoading = true;
  int _lastKnownVersion = 0;
  OthersProfileService get _othersProfileService => MessageProcessor.othersProfileService;
  StreamSubscription? _stateSubscription;
  String? _lastAvatarUrl;
  Timer? _reloadTimer;
  
  @override
  void initState() {
    super.initState();
    _loadGroupAvatar();
    _setupMatrixListener();
  }
  
  void _setupMatrixListener() {
    // Only setup listener for custom homeservers
    final roomService = Provider.of<RoomService>(context, listen: false);
    final homeserver = roomService.getMyHomeserver();
    if (utils.isCustomHomeserver(homeserver)) {
      final client = Provider.of<Client>(context, listen: false);
      final room = client.getRoomById(widget.roomId);
      if (room != null) {
        // Store initial avatar URL
        _lastAvatarUrl = room.avatar?.toString();
        
        // Listen for sync events and filter for this room
        _stateSubscription = client.onSync.stream
            .where((sync) => sync.rooms?.join?.containsKey(widget.roomId) ?? false)
            .listen((_) {
          // Check if avatar changed
          final room = client.getRoomById(widget.roomId);
          if (room != null) {
            final newAvatarUrl = room.avatar?.toString();
            if (newAvatarUrl != _lastAvatarUrl) {
              print('[CachedGroupAvatar] Avatar URL changed for room ${widget.roomId}');
              print('[CachedGroupAvatar] Old: $_lastAvatarUrl');
              print('[CachedGroupAvatar] New: $newAvatarUrl');
              _lastAvatarUrl = newAvatarUrl;
              
              // Cancel any pending reload
              _reloadTimer?.cancel();
              
              // Schedule reload with a small delay to ensure Matrix client is updated
              _reloadTimer = Timer(Duration(milliseconds: 100), () {
                if (mounted) {
                  _onAvatarChanged();
                }
              });
            }
          }
        });
      }
    }
  }
  
  Future<void> _onAvatarChanged() async {
    print('[CachedGroupAvatar] Processing avatar change for room ${widget.roomId}');
    
    // Clear cache
    final cacheDir = await getApplicationDocumentsDirectory();
    final cacheFile = File('${cacheDir.path}/room_avatar_${widget.roomId}');
    if (await cacheFile.exists()) {
      await cacheFile.delete();
      print('[CachedGroupAvatar] Cleared cache file for room ${widget.roomId}');
    }
    
    // Clear internal state to force UI update
    if (mounted) {
      setState(() {
        _avatarBytes = null;
        _isLoading = true;
      });
    }
    
    // Add a small delay to ensure server has processed the change
    await Future.delayed(Duration(milliseconds: 200));
    
    // Reload avatar
    if (mounted) {
      print('[CachedGroupAvatar] Reloading avatar for room ${widget.roomId}');
      _loadGroupAvatar();
    }
  }
  
  @override
  void dispose() {
    _stateSubscription?.cancel();
    _reloadTimer?.cancel();
    super.dispose();
  }
  
  @override
  void didUpdateWidget(CachedGroupAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _loadGroupAvatar();
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if the provider indicates this avatar was updated
    final profileProvider = Provider.of<ProfilePictureProvider>(context, listen: false);
    final currentVersion = profileProvider.getGroupAvatarVersion(widget.roomId);
    
    if (currentVersion > _lastKnownVersion) {
      print('CachedGroupAvatar: Version changed for ${widget.roomId} from $_lastKnownVersion to $currentVersion');
      _lastKnownVersion = currentVersion;
      // Force reload the avatar
      _loadGroupAvatar();
    }
  }
  
  Future<void> _loadGroupAvatar() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _avatarBytes = null; // Clear old avatar to force refresh
    });
    
    try {
      // Check if custom homeserver
      final roomService = Provider.of<RoomService>(context, listen: false);
      final homeserver = roomService.getMyHomeserver();
      final isCustomServer = utils.isCustomHomeserver(homeserver);
      
      if (isCustomServer) {
        // For custom homeservers, check Matrix room avatar first
        final matrixAvatar = await _loadMatrixRoomAvatar();
        if (matrixAvatar != null && mounted) {
          setState(() {
            _avatarBytes = matrixAvatar;
            _isLoading = false;
          });
          return;
        }
      } else {
        // For default server, use encrypted group avatar
        final bytes = await _othersProfileService.getCachedGroupAvatar(widget.roomId);
        
        if (bytes != null && mounted) {
          setState(() {
            _avatarBytes = bytes;
            _isLoading = false;
          });
          return;
        }
      }
      
      // No avatar found
      if (mounted) {
        setState(() {
          _avatarBytes = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading group avatar: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<Uint8List?> _loadMatrixRoomAvatar() async {
    try {
      final client = Provider.of<Client>(context, listen: false);
      final room = client.getRoomById(widget.roomId);
      if (room == null) {
        print('[CachedGroupAvatar] Room not found: ${widget.roomId}');
        return null;
      }
      
      final avatarUrl = room.avatar;
      if (avatarUrl == null) {
        print('[CachedGroupAvatar] No avatar URL for room: ${widget.roomId}');
        return null;
      }
      
      // Generate cache file path based on avatar URL to invalidate on change
      final cacheDir = await getApplicationDocumentsDirectory();
      final urlHash = avatarUrl.toString().hashCode.toString();
      final cacheFile = File('${cacheDir.path}/room_avatar_${widget.roomId}_$urlHash.jpg');
      
      // Clean up old cache files with different hashes
      final dir = Directory(cacheDir.path);
      final pattern = 'room_avatar_${widget.roomId}_';
      await for (final file in dir.list()) {
        if (file is File && file.path.contains(pattern) && !file.path.endsWith('_$urlHash.jpg')) {
          try {
            await file.delete();
            print('[CachedGroupAvatar] Deleted old cache: ${file.path}');
          } catch (e) {
            // Ignore deletion errors
          }
        }
      }
      
      // Check if current avatar is cached
      if (await cacheFile.exists()) {
        print('[CachedGroupAvatar] Using cached avatar for room: ${widget.roomId}');
        return await cacheFile.readAsBytes();
      }
      
      // Download from Matrix server
      print('[CachedGroupAvatar] Downloading avatar from server for room: ${widget.roomId}');
      final homeserverUrl = client.homeserver;
      final mxcParts = avatarUrl.toString().replaceFirst('mxc://', '').split('/');
      if (mxcParts.length == 2) {
        final serverName = mxcParts[0];
        final mediaId = mxcParts[1];
        final downloadUri = Uri.parse('$homeserverUrl/_matrix/media/v3/download/$serverName/$mediaId');
        
        final response = await client.httpClient.get(downloadUri);
        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          // Cache with URL-based filename
          await cacheFile.writeAsBytes(bytes);
          print('[CachedGroupAvatar] Cached new avatar for room: ${widget.roomId}');
          return bytes;
        } else {
          print('[CachedGroupAvatar] Failed to download avatar: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('[CachedGroupAvatar] Error loading Matrix room avatar: $e');
    }
    return null;
  }
  
  @override
  Widget build(BuildContext context) {
    // Listen to provider but only for this specific room's updates
    final profileProvider = Provider.of<ProfilePictureProvider>(context);
    
    // Check for version changes specific to this room
    final currentVersion = profileProvider.getGroupAvatarVersion(widget.roomId);
    if (currentVersion > _lastKnownVersion) {
      _lastKnownVersion = currentVersion;
      // Schedule a reload after the current build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          print('CachedGroupAvatar: Reloading due to version change for ${widget.roomId}');
          _loadGroupAvatar();
        }
      });
    }
    
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: 300),
        child: _buildAvatarContent(),
      ),
    );
  }
  
  Widget _buildAvatarContent() {
    if (_isLoading) {
      return SizedBox(
        width: widget.radius * 1.2,
        height: widget.radius * 1.2,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      );
    }
    
    // If we have a group avatar, show it
    if (_avatarBytes != null) {
      return ClipOval(
        child: Image.memory(
          _avatarBytes!,
          width: widget.radius * 2,
          height: widget.radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to triangle avatars on error
            return _buildTriangleAvatars();
          },
        ),
      );
    }
    
    // Otherwise show triangle avatars
    return _buildTriangleAvatars();
  }
  
  Widget _buildTriangleAvatars() {
    // Remove the CircleAvatar wrapper since TriangleAvatars handles its own shape
    return SizedBox(
      width: widget.radius * 2,
      height: widget.radius * 2,
      child: TriangleAvatars(
        userIds: widget.memberIds.take(3).toList(),
      ),
    );
  }
}