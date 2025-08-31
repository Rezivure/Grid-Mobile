import 'package:flutter/material.dart';
import 'user_avatar_bloc.dart';

/// A wrapper widget that ensures UserAvatarBloc updates are reflected in lists
/// With the new BLoC pattern, this is now just a simple wrapper that passes through to UserAvatarBloc
class AvatarWithUpdates extends StatelessWidget {
  final String userId;
  final double size;
  
  const AvatarWithUpdates({
    Key? key,
    required this.userId,
    required this.size,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // UserAvatarBloc already handles updates through the BLoC pattern
    return UserAvatarBloc(
      userId: userId,
      size: size,
    );
  }
}