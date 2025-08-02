import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import '../services/avatar_cache_service.dart';
import '../blocs/avatar/avatar_bloc.dart';
import '../blocs/avatar/avatar_event.dart';
import '../blocs/map/map_bloc.dart';
import '../blocs/map/map_event.dart';
import '../services/sync_manager.dart';
import '../widgets/user_avatar.dart';

class AppLifecycleWrapper extends StatefulWidget {
  final Widget child;
  
  const AppLifecycleWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);
  
  @override
  _AppLifecycleWrapperState createState() => _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends State<AppLifecycleWrapper> with WidgetsBindingObserver {
  DateTime? _pausedTime;
  bool _isResuming = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[AppLifecycle] State changed to: $state');
    
    switch (state) {
      case AppLifecycleState.paused:
        _pausedTime = DateTime.now();
        print('[AppLifecycle] App paused at $_pausedTime');
        break;
        
      case AppLifecycleState.resumed:
        if (!_isResuming) {
          _isResuming = true;
          _handleAppResume();
        }
        break;
        
      default:
        break;
    }
  }
  
  Future<void> _handleAppResume() async {
    try {
      print('[AppLifecycle] App resumed - handling resume sequence');
      
      // Calculate how long the app was paused
      final pauseDuration = _pausedTime != null 
          ? DateTime.now().difference(_pausedTime!) 
          : Duration.zero;
      
      print('[AppLifecycle] App was paused for: ${pauseDuration.inMinutes} minutes');
      
      // If app was paused for more than 5 minutes, do a full refresh
      if (pauseDuration.inMinutes > 5) {
        print('[AppLifecycle] Long pause detected - performing full refresh');
        
        // Reinitialize avatar cache from persistent storage
        final cacheService = AvatarCacheService();
        await cacheService.reloadFromPersistent();
        
        // Refresh all avatars through the bloc
        if (mounted && context.mounted) {
          context.read<AvatarBloc>().add(RefreshAllAvatars());
        }
        
        // Force a visual update of all avatar widgets
        await Future.delayed(const Duration(milliseconds: 300));
        UserAvatar.notifyAvatarUpdated('*');
        
        // Reload user locations on the map
        if (mounted && context.mounted) {
          context.read<MapBloc>().add(MapLoadUserLocations());
        }
        
        // Trigger a full sync
        if (mounted && context.mounted) {
          final syncManager = context.read<SyncManager>();
          syncManager.handleAppLifecycleState(true);
        }
      } else {
        print('[AppLifecycle] Short pause - performing light refresh');
        
        // For shorter pauses, just notify avatar widgets to check their cache
        UserAvatar.notifyAvatarUpdated('*');
        
        // Light sync
        if (mounted && context.mounted) {
          final syncManager = context.read<SyncManager>();
          syncManager.handleAppLifecycleState(true);
        }
      }
      
      // Force a rebuild of the widget tree
      if (mounted) {
        setState(() {});
      }
      
    } catch (e) {
      print('[AppLifecycle] Error handling app resume: $e');
    } finally {
      _isResuming = false;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}