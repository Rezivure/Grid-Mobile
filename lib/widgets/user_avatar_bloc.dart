import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:random_avatar/random_avatar.dart';
import '../utilities/utils.dart';
import '../blocs/avatar/avatar_bloc.dart';
import '../blocs/avatar/avatar_event.dart';
import '../blocs/avatar/avatar_state.dart';

class UserAvatarBloc extends StatefulWidget {
  final String userId;
  final double size;

  const UserAvatarBloc({
    Key? key,
    required this.userId,
    this.size = 40,
  }) : super(key: key);

  @override
  _UserAvatarBlocState createState() => _UserAvatarBlocState();
}

class _UserAvatarBlocState extends State<UserAvatarBloc> {
  @override
  void initState() {
    super.initState();
    // Request avatar load when widget is created
    context.read<AvatarBloc>().add(LoadAvatar(widget.userId));
  }

  @override
  void didUpdateWidget(UserAvatarBloc oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload avatar if userId changed
    if (oldWidget.userId != widget.userId) {
      context.read<AvatarBloc>().add(LoadAvatar(widget.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AvatarBloc, AvatarState>(
      buildWhen: (previous, current) {
        // Rebuild when this specific user's avatar changes or update counter changes
        return previous.getAvatar(widget.userId) != current.getAvatar(widget.userId) ||
               previous.updateCounter != current.updateCounter ||
               previous.isLoading(widget.userId) != current.isLoading(widget.userId);
      },
      builder: (context, state) {
        final avatarData = state.getAvatar(widget.userId);
        final isLoading = state.isLoading(widget.userId);
        
        // If we have avatar data, show it
        if (avatarData != null) {
          return ClipOval(
            child: Image.memory(
              avatarData,
              fit: BoxFit.cover,
              width: widget.size,
              height: widget.size,
              gaplessPlayback: true, // Prevent flicker when updating
            ),
          );
        }
        
        // If no avatar data and not loading, request it
        if (!isLoading && avatarData == null) {
          // Request avatar load on next frame to avoid building during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.read<AvatarBloc>().add(LoadAvatar(widget.userId));
            }
          });
        }
        
        // Show loading indicator if loading
        if (isLoading) {
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
      },
    );
  }
}