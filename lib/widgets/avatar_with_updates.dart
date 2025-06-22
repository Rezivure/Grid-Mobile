import 'package:flutter/material.dart';
import 'user_avatar.dart';

/// A wrapper widget that ensures UserAvatar updates are reflected in lists
class AvatarWithUpdates extends StatefulWidget {
  final String userId;
  final double size;
  
  const AvatarWithUpdates({
    Key? key,
    required this.userId,
    required this.size,
  }) : super(key: key);
  
  @override
  State<AvatarWithUpdates> createState() => _AvatarWithUpdatesState();
}

class _AvatarWithUpdatesState extends State<AvatarWithUpdates> {
  @override
  void initState() {
    super.initState();
    UserAvatar.avatarUpdateNotifier.addListener(_onAvatarUpdate);
  }
  
  @override
  void dispose() {
    UserAvatar.avatarUpdateNotifier.removeListener(_onAvatarUpdate);
    super.dispose();
  }
  
  void _onAvatarUpdate() {
    final updatedUserId = UserAvatar.avatarUpdateNotifier.value;
    if (updatedUserId == widget.userId && mounted) {
      print('[AvatarWithUpdates] Received update for ${widget.userId}, rebuilding...');
      setState(() {});
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      userId: widget.userId,
      size: widget.size,
    );
  }
}