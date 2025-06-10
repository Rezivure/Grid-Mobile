import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'package:grid_frontend/providers/profile_picture_provider.dart';
import 'package:grid_frontend/services/others_profile_service.dart';
import 'package:grid_frontend/widgets/triangle_avatars.dart';

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
  final OthersProfileService _othersProfileService = OthersProfileService();
  
  @override
  void initState() {
    super.initState();
    _loadGroupAvatar();
  }
  
  @override
  void didUpdateWidget(CachedGroupAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _loadGroupAvatar();
    }
  }
  
  Future<void> _loadGroupAvatar() async {
    setState(() => _isLoading = true);
    
    try {
      // Try to get group avatar first
      final bytes = await _othersProfileService.getCachedGroupAvatar(widget.roomId);
      
      if (mounted) {
        setState(() {
          _avatarBytes = bytes;
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
  
  @override
  Widget build(BuildContext context) {
    // Listen to provider for updates
    final profileProvider = context.watch<ProfilePictureProvider>();
    
    // Check if this group's avatar was updated
    if (profileProvider.wasProfileUpdated(widget.roomId)) {
      // Reload the group avatar
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadGroupAvatar();
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