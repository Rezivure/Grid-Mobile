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

class _UserAvatarBlocState extends State<UserAvatarBloc> with WidgetsBindingObserver {
  AppLifecycleState? _lifecycleState;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    
    // Only load avatar if app is in foreground
    if (_lifecycleState != AppLifecycleState.paused && 
        _lifecycleState != AppLifecycleState.detached) {
      context.read<AvatarBloc>().add(LoadAvatar(widget.userId));
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _lifecycleState = state;
    });
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
    // Don't try to render images if app is in background
    if (_lifecycleState == AppLifecycleState.paused || 
        _lifecycleState == AppLifecycleState.detached) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Container(), // Empty container while in background
      );
    }
    
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
        if (avatarData != null && avatarData.isNotEmpty) {
          // Use a key to force recreation of the Image widget when needed
          final imageKey = ValueKey('avatar_${widget.userId}_${state.updateCounter}');
          
          return ClipOval(
            child: Image.memory(
              avatarData,
              key: imageKey,
              fit: BoxFit.cover,
              width: widget.size,
              height: widget.size,
              gaplessPlayback: true, // Prevent flicker when updating
              cacheWidth: (widget.size * 2).toInt(), // Limit texture size
              cacheHeight: (widget.size * 2).toInt(), // Limit texture size
              errorBuilder: (context, error, stackTrace) {
                // Check if it's a GPU error
                if (error.toString().contains('GPU') || error.toString().contains('loss of GPU')) {
                  print('[Avatar] GPU error detected, reinitializing for ${widget.userId}');
                  // Schedule a reinit on the next frame
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      // Force a refresh of this avatar
                      context.read<AvatarBloc>().add(ClearAvatarCache(widget.userId));
                      context.read<AvatarBloc>().add(LoadAvatar(widget.userId));
                    }
                  });
                }
                // Fall back to RandomAvatar on error
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
            ),
          );
        }
        
        // If no avatar data and not loading, request it (unless it recently failed)
        if (!isLoading && avatarData == null && !state.hasRecentlyFailed(widget.userId)) {
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