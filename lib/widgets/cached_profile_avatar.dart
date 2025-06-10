import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'dart:typed_data';
import 'package:grid_frontend/providers/profile_picture_provider.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;

class CachedProfileAvatar extends StatefulWidget {
  final String userId;
  final double radius;
  final String? displayName;
  
  const CachedProfileAvatar({
    Key? key,
    required this.userId,
    this.radius = 20,
    this.displayName,
  }) : super(key: key);

  @override
  _CachedProfileAvatarState createState() => _CachedProfileAvatarState();
}

class _CachedProfileAvatarState extends State<CachedProfileAvatar> {
  Uint8List? _profileBytes;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadProfilePicture();
  }
  
  @override
  void didUpdateWidget(CachedProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _loadProfilePicture();
    }
  }
  
  Future<void> _loadProfilePicture() async {
    setState(() => _isLoading = true);
    
    final provider = Provider.of<ProfilePictureProvider>(context, listen: false);
    final bytes = await provider.getProfilePicture(widget.userId);
    
    if (mounted) {
      setState(() {
        _profileBytes = bytes;
        _isLoading = false;
      });
    }
  }
  
  String _getLocalpart() {
    return utils.localpart(widget.userId);
  }
  
  @override
  Widget build(BuildContext context) {
    // Listen to provider for updates
    final profileProvider = context.watch<ProfilePictureProvider>();
    
    // Check if this user's profile was updated
    if (profileProvider.wasProfileUpdated(widget.userId)) {
      // Reload the profile picture
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadProfilePicture();
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
    
    if (_profileBytes != null) {
      return ClipOval(
        child: Image.memory(
          _profileBytes!,
          width: widget.radius * 2,
          height: widget.radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to default avatar on error
            return _buildDefaultAvatar();
          },
        ),
      );
    }
    
    return _buildDefaultAvatar();
  }
  
  Widget _buildDefaultAvatar() {
    // Always use localpart for consistency with existing RandomAvatar usage
    final localpart = _getLocalpart();
    return RandomAvatar(
      localpart,
      height: widget.radius * 1.6,
      width: widget.radius * 1.6,
    );
  }
}