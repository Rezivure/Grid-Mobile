import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vector_renderer;
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/blocs/map/map_state.dart';
import 'package:grid_frontend/blocs/avatar/avatar_bloc.dart';
import 'package:grid_frontend/blocs/avatar/avatar_event.dart';
import 'package:grid_frontend/services/avatar_cache_service.dart';
import 'package:grid_frontend/blocs/map_icons/map_icons_bloc.dart';
import 'package:grid_frontend/blocs/map_icons/map_icons_event.dart';
import 'package:grid_frontend/blocs/map_icons/map_icons_state.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/widgets/user_map_marker.dart';
import 'package:grid_frontend/widgets/map_scroll_window.dart';
import 'package:grid_frontend/widgets/user_info_bubble.dart';
import 'package:grid_frontend/widgets/user_avatar.dart';
import 'package:grid_frontend/screens/settings/settings_page.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/widgets/onboarding_modal.dart';
import 'package:grid_frontend/services/subscription_service.dart';
import 'package:grid_frontend/screens/settings/subscription_screen.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/widgets/app_initializer.dart';
import 'package:grid_frontend/widgets/icon_selection_wheel.dart';
import 'package:grid_frontend/widgets/icon_action_wheel.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/models/map_icon.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/widgets/map_icon_info_bubble.dart';
import 'package:grid_frontend/widgets/app_review_prompt.dart';
import 'package:uuid/uuid.dart';
import 'package:grid_frontend/services/map_icon_sync_service.dart';

import '../../services/backwards_compatibility_service.dart';

// Helper class to return both zoom and center point
class MapZoomResult {
  final double zoom;
  final LatLng center;
  
  MapZoomResult({required this.zoom, required this.center});
}

class MapTab extends StatefulWidget {
  final LatLng? friendLocation;
  const MapTab({this.friendLocation, Key? key}) : super(key: key);

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with TickerProviderStateMixin, WidgetsBindingObserver {
  static bool _hasInitialized = false;
  static DateTime? _lastInitTime;
  bool _servicesInitialized = false;
  AppLifecycleState? _currentLifecycleState;
  late MapController _mapController;
  LocationManager? _locationManager;
  RoomService? _roomService;
  UserService? _userService;
  SyncManager? _syncManager;
  UserRepository? userRepository;
  SharingPreferencesRepository? sharingPreferencesRepository;
  MapIconRepository? _mapIconRepository;
  MapIconSyncService? _mapIconSyncService;
  SelectedSubscreenProvider? _subscreenProvider;

  bool _isMapReady = false;
  bool _followUser = false;  // Changed default to false to prevent initial movement
  double _zoom = 3.5;  // Default to full country view for faster tile loading
  bool _initialZoomCalculated = false;
  LatLng? _initialCenter;  // Store the calculated center point
  int _lastKnownUserLocationsCount = 0;  // Track when contacts first load from sync

  // Track if we're at the reset view for FAB highlighting
  bool _isAtResetView = true;
  LatLng? _resetCenter;
  double? _resetZoom;

  bool _isPingOnCooldown = false;
  int _pingCooldownSeconds = 5;
  Timer? _pingCooldownTimer;

  VectorTileProvider? _tileProvider;
  late vector_renderer.Theme _mapTheme;

  // Bubble variables
  LatLng? _bubblePosition;
  String? _selectedUserId;
  String? _selectedUserName;

  AnimationController? _animationController;
  
  // Map rotation tracking
  double _currentMapRotation = 0.0;
  
  // Track map movement completion
  Timer? _mapMoveTimer;
  String? _targetUserId;
  
  // Track app pause time for restart logic
  DateTime? _pausedTime;
  
  // Map style selector
  bool _showMapSelector = false;
  String? _currentMapStyle; // null until loaded from preferences
  bool _isLoadingMapStyle = false;

  // Force map rebuild when coming from background
  Key _mapKey = UniqueKey();
  
  // Icon selection wheel
  bool _showIconWheel = false;
  Offset? _iconWheelPosition;
  LatLng? _longPressLocation;
  String? _selectedGroupId;
  
  // Track if editing map icon description
  bool _isEditingIconDescription = false;
  
  // Selected map icon for info bubble
  MapIcon? _selectedMapIcon;
  LatLng? _selectedIconPosition;
  
  // Icon action wheel
  bool _showIconActionWheel = false;
  Offset? _iconActionWheelPosition;
  
  // Move mode for dragging icons
  bool _isMovingIcon = false;
  MapIcon? _movingIcon;
  
  // Avatar check timer - removed to prevent refresh loops
  final SubscriptionService _subscriptionService = SubscriptionService();
  String? _satelliteMapToken;
  
  // SharedPreferences keys
  static const String _mapStyleKey = 'selected_map_style';

  @override
  void initState() {
    super.initState();
    print('[MapTab] Initializing - hasInitialized: $_hasInitialized');
    WidgetsBinding.instance.addObserver(this);
    _mapController = MapController();
    
    // Check if app was properly initialized
    _checkAndInitialize().then((_) {
      // Only access _locationManager after initialization is complete
      if (mounted) {
      }
    });
    
    // Start review manager session
    AppReviewManager.startSession();
    
    // Show onboarding modal if user hasn't seen it yet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OnboardingModal.showOnboardingIfNeeded(context);
      
      // Schedule review prompt check for later (after user has used the app for a bit)
      _scheduleReviewPromptCheck();
    });
  }
  
  Future<void> _checkAndInitialize() async {
    // Always just do normal initialization now that avatar issue is fixed
    // Defer to next frame to avoid build phase conflicts
    await Future.delayed(Duration.zero);
    if (!mounted) return;

    await _initializeServices();

    // Load map style preference FIRST before loading map provider
    await _loadMapStylePreference();

    // Check if app was launched from background (terminated state)
    // This happens when background location updates wake the app
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    final wasLaunchedFromBackground = lifecycleState == AppLifecycleState.resumed ||
        lifecycleState == AppLifecycleState.inactive;

    if (wasLaunchedFromBackground) {
      print('[MapTab] App launched from background/terminated state - forcing tile provider reinitialization');
      // Clear tile provider first to ensure complete reinitialization
      _tileProvider = null;
    }

    await _loadMapProvider();

    // Only force rebuild if actually launched from background AND tile provider exists
    if (wasLaunchedFromBackground && _tileProvider != null) {
      // Single setState to trigger UI update after everything is loaded
      if (mounted) {
        setState(() {
          print('[MapTab] UI refreshed after background launch');
        });
      }
    }
  }
  
  // Keeping this function for potential future use, but no longer needed after avatar fix
  Future<void> _forceFullInitialization() async {
    print('[MapTab] Starting forced reinitialization');
    
    // CRITICAL: Force Flutter to recreate its rendering context
    // This fixes the GPU access loss issue
    WidgetsFlutterBinding.ensureInitialized();
    
    // Give the engine a moment to reset
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Reinitialize avatar cache
    final avatarCacheService = AvatarCacheService();
    await avatarCacheService.reloadFromPersistent();
    
    // Reinitialize services
    await _initializeServices();
    _loadMapProvider();
    _loadMapStylePreference();
    
    // Clear and reload avatars
    if (mounted && context.mounted) {
      // Clear the avatar cache first to force fresh load
      context.read<AvatarBloc>().add(ClearAvatarCache());
      await Future.delayed(const Duration(milliseconds: 100));
      context.read<AvatarBloc>().add(RefreshAllAvatars());
      
      // Force reload map data
      context.read<MapBloc>().add(MapLoadUserLocations());
    }
    
    // Force a complete widget rebuild
    if (mounted) {
      setState(() {});
    }
    
    print('[MapTab] Reinitialization complete');
  }

  void _scheduleReviewPromptCheck() {
    // Check for review prompt every 5 minutes to see if user has met usage criteria
    Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        AppReviewManager.showReviewPromptIfNeeded(context).then((shown) {
          // If prompt was shown, cancel the timer
          if (shown == true) {
            timer.cancel();
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _initializeServices() async {
    // Skip if already initialized
    if (_servicesInitialized) {
      // Still need to re-add listeners that might have been removed
      _locationManager?.addListener(_onLocationUpdate);
      _syncManager?.addListener(_checkAuthenticationStatus);
      _subscreenProvider = context.read<SelectedSubscreenProvider>();
      _subscreenProvider?.addListener(_onSubscreenChanged);
      return;
    }
    
    _roomService = context.read<RoomService>();
    _userService = context.read<UserService>();
    _locationManager = context.read<LocationManager>();
    _syncManager = context.read<SyncManager>();
    userRepository = context.read<UserRepository>();
    sharingPreferencesRepository = context.read<SharingPreferencesRepository>();
    
    _servicesInitialized = true;
    
    // Initialize map icon repository and sync service
    final databaseService = context.read<DatabaseService>();
    final client = context.read<Client>();
    _mapIconRepository = MapIconRepository(databaseService);
    _mapIconSyncService = MapIconSyncService(
      client: client,
      mapIconRepository: _mapIconRepository,
      mapIconsBloc: context.read<MapIconsBloc>(),
    );
    
    // Load existing icons for current selection
    _loadMapIcons();
    
    // Listen for subscreen changes to reload icons
    context.read<SelectedSubscreenProvider>().addListener(_onSubscreenChanged);

    // Listen for authentication failures
    _syncManager?.addListener(_checkAuthenticationStatus);

    // Initialize sync manager and listen for state changes
    _syncManager?.addListener(_onSyncStateChanged);
    _syncManager?.initialize();

    // Queue orphaned data cleanup to run after sync completes
    _syncManager?.queuePostSyncOperation(() async {
      try {
        await _syncManager?.cleanupOrphanedLocationData();
      } catch (e) {
        print('[MapTab] Error cleaning orphaned data: $e');
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final isIncognitoMode = prefs.getBool('incognito_mode') ?? false;

    if (!isIncognitoMode) {
      _locationManager?.startTracking();
      // Immediately try to get current location to avoid showing default location
      _locationManager?.grabLocationAndPing().then((_) {
        if (mounted && _locationManager?.currentLatLng != null && _isMapReady && !_initialZoomCalculated) {
          // If map is ready and we haven't zoomed yet, do it now
          _zoom = 3.5; // Full country view for faster loading
          _mapController.moveAndRotate(_locationManager!.currentLatLng!, _zoom, 0);
          // Don't setState here - let _onLocationUpdate handle it to avoid double setState
          _initialZoomCalculated = true;
        }
      });
    }
    
    // Listen for location updates to trigger zoom calculation
    _locationManager?.addListener(_onLocationUpdate);
    
    // Load avatars ONCE on init without any refresh loops
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _loadAvatarsOnce();
      }
    });
  }
  
  // Removed periodic avatar check to prevent refresh loops
  
  void _loadAvatarsOnce() async {
    // Wait a moment for the UI to settle
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted) return;
    
    final avatarBloc = context.read<AvatarBloc>();
    
    
    // Initialize the avatar cache service if needed
    await avatarBloc.cacheService.initialize();
    
    if (!mounted) return;
    
    // Get all user IDs that might need avatars
    final mapBloc = context.read<MapBloc>();
    final userLocations = mapBloc.state.userLocations;
    
    // Request load for each user location
    for (final userLocation in userLocations) {
      avatarBloc.add(LoadAvatar(userLocation.userId));
    }
    
    // Also load current user's avatar
    final client = context.read<Client>();
    if (client.userID != null) {
      avatarBloc.add(LoadAvatar(client.userID!));
    }
    
    // That's it - no restarts, no loops, just load avatars once
  }
  
  void _onLocationUpdate() {
    // Check if we can calculate zoom now
    if (!_initialZoomCalculated && _isMapReady && _locationManager?.currentLatLng != null) {
      // Mark as calculated immediately to prevent multiple calls
      _initialZoomCalculated = true;

      // Get user locations to determine optimal view
      final mapBloc = context.read<MapBloc>();
      final userLocations = mapBloc.state.userLocations;

      if (userLocations.isNotEmpty) {
        // Calculate optimal view including contacts
        final result = _calculateOptimalZoomAndCenter(
          _locationManager!.currentLatLng!,
          userLocations
        );
        _zoom = result.zoom;
        _resetCenter = result.center;
        _resetZoom = result.zoom;
        _mapController.moveAndRotate(result.center, _zoom, 0);
      } else {
        // No contacts yet, just center on user
        _zoom = 3.5; // Full country view for faster loading
        _resetCenter = _locationManager!.currentLatLng!;
        _resetZoom = 3.5;
        _mapController.moveAndRotate(_locationManager!.currentLatLng!, _zoom, 0);
      }

      // Single setState at the end
      if (mounted) {
        setState(() {
          _isAtResetView = true;
        });
      }
    }
  }

  void _checkAuthenticationStatus() {
    if (_syncManager?.authenticationFailed == true) {
      // Authentication failed, navigate to login screen
      
      // Clear the flag so we don't repeatedly navigate
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
        }
      });
    }
  }
  
  void _onSubscreenChanged() {
    if (!mounted) return;

    // Reload icons when the selected subscreen changes
    _loadMapIcons();

    // Clear selected icon if subscreen changes
    if (mounted) {
      setState(() {
        _selectedMapIcon = null;
        _selectedIconPosition = null;
      });
    }
  }

  void _onSyncStateChanged() {
    // React to sync state changes if needed
    if (_syncManager?.isReady == true && !_hasStartedLocationTracking) {
      _hasStartedLocationTracking = true;
      print('[MapTab] Sync ready, location tracking can proceed');
    }
  }
  
  bool _hasStartedLocationTracking = false;
  
  @override
  void dispose() {
    _syncManager?.removeListener(_onSyncStateChanged);
    _animationController?.dispose();
    _mapMoveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _locationManager?.removeListener(_onLocationUpdate);
    _syncManager?.removeListener(_checkAuthenticationStatus);
    _syncManager?.removeListener(_onSyncStateChanged);
    _subscreenProvider?.removeListener(_onSubscreenChanged);
    _mapController.dispose();
    _syncManager?.stopSync();
    _locationManager?.stopTracking();
    AppReviewManager.stopSession(); // Stop tracking usage
    
    // No longer need to reset initialization flag
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    print('[MapTab] Lifecycle: $state');
    
    // Store current lifecycle state
    _currentLifecycleState = state;
    
    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now();
      AppReviewManager.stopSession(); // Pause usage tracking when app goes to background
      
      // No longer need to reset initialization flag when going to background
      
    } else if (state == AppLifecycleState.resumed) {
      AppReviewManager.startSession(); // Resume usage tracking when app comes back
      
      // No longer need special handling for background launch
    }
    
    if (state == AppLifecycleState.resumed && _pausedTime != null) {
      final pauseDuration = DateTime.now().difference(_pausedTime!);
      
      // If app was paused for more than 30 seconds, restart from splash
      if (pauseDuration.inSeconds > 30) {
        print('[MapTab] Long pause detected (${pauseDuration.inSeconds}s) - restarting');
        
        // Navigate to splash screen to ensure full initialization
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => AppInitializer(client: context.read<Client>()),
            ),
            (route) => false,
          );
        }
        return;
      }
    }
    
    // Normal resume handling for short pauses
    _syncManager?.handleAppLifecycleState(state == AppLifecycleState.resumed);
    
    // Refresh satellite token when app resumes if using satellite maps
    if (state == AppLifecycleState.resumed && _currentMapStyle == 'satellite') {
      _refreshSatelliteTokenIfNeeded();
    }
    
    // Only reinitialize if app was paused for a significant time
    if (state == AppLifecycleState.resumed && _pausedTime != null) {
      final pauseDuration = DateTime.now().difference(_pausedTime!);

      // Only rebuild if paused for more than 5 seconds (to handle background location wakes)
      if (pauseDuration.inSeconds > 5 && _tileProvider != null) {
        print('[MapTab] App resumed after ${pauseDuration.inSeconds}s - rebuilding map');

        // Single rebuild after short delay
        Future.delayed(const Duration(milliseconds: 400), () async {
          if (mounted && _isMapReady) {
            // Store current position
            final currentCenter = _mapController.camera.center;
            final currentZoom = _mapController.camera.zoom;

            // Reload the tile provider
            await _loadMapProvider();

            // Single map rebuild
            setState(() {
              _mapKey = UniqueKey();
              print('[MapTab] Map rebuilt after resume');
            });

            // Restore position after rebuild
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted && _isMapReady && currentCenter != null) {
                _mapController.move(currentCenter, currentZoom);
              }
            });
          }
        });
      }
    }
  }

  void _backwardsCompatibilityUpdate() async {
    if (userRepository == null || sharingPreferencesRepository == null) {
      return; // Services not yet initialized
    }
    
    final backwardsService = BackwardsCompatibilityService(
      userRepository!,
      sharingPreferencesRepository!,
    );

    await backwardsService.runBackfillIfNeeded();
  }
  
  Future<void> _refreshSatelliteTokenIfNeeded() async {
    try {
      // Check if still has subscription
      final hasSubscription = await _subscriptionService.hasActiveSubscription();
      if (!hasSubscription) {
        // Subscription expired, revert to base maps
        setState(() {
          _currentMapStyle = 'base';
          _satelliteMapToken = null;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_mapStyleKey, 'base');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Subscription expired. Reverting to base maps.'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        return;
      }
      
      // Get a fresh token (will use cached if still valid)
      final token = await _subscriptionService.getMapToken();
      if (token != null && token != _satelliteMapToken) {
        setState(() {
          _satelliteMapToken = token;
        });
      }
    } catch (e) {
    }
  }

  void _handleIconSelection(IconType iconType) async {
    if (_longPressLocation == null || _selectedGroupId == null) return;
    
    // Immediately close the wheel for instant feedback
    setState(() {
      _showIconWheel = false;
      _iconWheelPosition = null;
    });
    
    // Get the current user ID
    final client = context.read<Client>();
    final creatorId = client.userID ?? 'unknown';
    
    // Create a new map icon
    final newIcon = MapIcon(
      id: const Uuid().v4(),
      roomId: _selectedGroupId!,
      creatorId: creatorId,
      latitude: _longPressLocation!.latitude,
      longitude: _longPressLocation!.longitude,
      iconType: 'icon',
      iconData: iconType.name,
      name: '${iconType.name.substring(0, 1).toUpperCase()}${iconType.name.substring(1)}',
      description: null,
      createdAt: DateTime.now(),
      expiresAt: null,
      metadata: null,
    );
    
    // Immediately add to BLoC for instant visual feedback
    context.read<MapIconsBloc>().add(MapIconCreated(newIcon));
    
    // Clear location references
    _longPressLocation = null;
    _selectedGroupId = null;
    
    // Show confirmation immediately with shorter duration
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${iconType.name.substring(0, 1).toUpperCase()}${iconType.name.substring(1)} icon placed'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(milliseconds: 1500),
      ),
    );
    
    // Save to database and sync in background
    try {
      await _mapIconRepository?.insertMapIcon(newIcon);
      await _mapIconSyncService?.sendIconCreate(newIcon.roomId, newIcon);
    } catch (e) {
      // If save fails, remove from BLoC
      context.read<MapIconsBloc>().add(MapIconDeleted(iconId: newIcon.id, roomId: newIcon.roomId));
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to save icon'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  
  Future<void> _loadMapIcons() async {
    try {
      // Get the currently selected subscreen
      final selectedSubscreen = context.read<SelectedSubscreenProvider>().selectedSubscreen;
      final mapIconsBloc = context.read<MapIconsBloc>();
      
      // Only load icons if a group is selected
      if (selectedSubscreen.startsWith('group:')) {
        final groupId = selectedSubscreen.substring(6);
        mapIconsBloc.add(LoadMapIcons(groupId));
      }
      // You can add support for individual DM rooms here if needed
      // else if (selectedSubscreen.startsWith('user:')) {
      //   final userId = selectedSubscreen.substring(5);
      //   // Get DM room ID and load icons
      // }
      else {
        // Clear icons if no group selected
        mapIconsBloc.add(ClearAllMapIcons());
      }
    } catch (e) {
    }
  }
  
  void _sendPing() {
    _locationManager?.grabLocationAndPing();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Location pinged to all active contacts and groups.'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );


    setState(() {
      _isPingOnCooldown = true;
      _pingCooldownSeconds = 10; // sets ping rate max
    });

    _pingCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _pingCooldownSeconds--;
      });

      if (_pingCooldownSeconds <= 0) {
        setState(() {
          _isPingOnCooldown = false;
        });
        timer.cancel();
      }
    });
  }

  Future<void> _loadMapProvider() async {
    try {
      // Ensure dotenv is loaded before proceeding
      if (dotenv.env.isEmpty) {
        try {
          await dotenv.load(fileName: ".env");
        } catch (e) {
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final mapUrl = prefs.getString('maps_url') ?? 'https://map.mygrid.app/v1/protomaps.pmtiles';

      // Clear existing tile provider to force complete reinitialization
      _tileProvider = null;

      _mapTheme = ProtomapsThemes.light();
      _tileProvider = await PmTilesVectorTileProvider.fromSource(mapUrl);

      context.read<MapBloc>().add(MapInitialize());
      setState(() {});
    } catch (e) {
      _showMapErrorDialog();
    }
  }
  
  Future<void> _loadMapStylePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStyle = prefs.getString(_mapStyleKey) ?? 'base';

      // Check if user has an active subscription before loading satellite maps
      if (savedStyle == 'satellite') {
        final hasSubscription = await _subscriptionService.hasActiveSubscription();
        if (hasSubscription) {
          // Try to get a map token (will use cached if valid)
          final token = await _subscriptionService.getMapToken();
          if (token != null) {
            // Set satellite style without setState since we're in init
            _currentMapStyle = 'satellite';
            _satelliteMapToken = token;
          } else {
            // Failed to get token, revert to base maps
            _currentMapStyle = 'base';
            await prefs.setString(_mapStyleKey, 'base');
          }
        } else {
          // No subscription, revert to base maps
          _currentMapStyle = 'base';
          await prefs.setString(_mapStyleKey, 'base');
        }
      } else {
        _currentMapStyle = savedStyle;
      }
    } catch (e) {
      // Default to base maps on error
      _currentMapStyle = 'base';
    }

    // If still null somehow, default to base
    _currentMapStyle ??= 'base';
  }

  void _showMapErrorDialog() {
    if (!mounted) return;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error icon with animation
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 48,
                  color: Colors.orange,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Title
              Text(
                'Connection Error',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Content
              Text(
                'Failed to connect and load Grid. Please check your internet connection.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                  height: 1.4,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Single retry button that restarts the app
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Navigate to splash screen to restart the app flow
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/', 
                      (Route<dynamic> route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  void _resetToInitialZoom() {
    // Reset to initial smart zoom calculation
    if (_locationManager?.currentLatLng != null) {
      final mapBloc = context.read<MapBloc>();
      final userLocations = mapBloc.state.userLocations;
      final colorScheme = Theme.of(context).colorScheme;

      LatLng center;
      double zoom;

      if (userLocations.isNotEmpty) {
        // Calculate optimal view including contacts
        final result = _calculateOptimalZoomAndCenter(
          _locationManager!.currentLatLng!,
          userLocations
        );
        center = result.center;
        zoom = result.zoom;
      } else {
        // No contacts, just center on user at country level
        center = _locationManager!.currentLatLng!;
        zoom = 3.5;
      }

      // Store reset position and zoom
      _resetCenter = center;
      _resetZoom = zoom;
      _zoom = zoom;

      // Move to reset position
      _mapController.moveAndRotate(center, zoom, 0);

      // Mark as at reset view and unlock follow mode
      setState(() {
        _isAtResetView = true;
        _followUser = false;  // Unlock follow mode when resetting
      });
    }
  }

  // Returns both optimal zoom and center point
  MapZoomResult _calculateOptimalZoomAndCenter(LatLng userPosition, List<UserLocation> userLocations) {
    print('[SmartZoom] Calculating optimal view for ${userLocations.length} contacts');

    if (userLocations.isEmpty) {
      return MapZoomResult(zoom: 4.5, center: userPosition);
    }

    // Calculate bounds that include ALL contacts plus the user
    double minLat = userPosition.latitude;
    double maxLat = userPosition.latitude;
    double minLng = userPosition.longitude;
    double maxLng = userPosition.longitude;

    // Find the bounding box of all users
    for (final location in userLocations) {
      minLat = minLat < location.position.latitude ? minLat : location.position.latitude;
      maxLat = maxLat > location.position.latitude ? maxLat : location.position.latitude;
      minLng = minLng < location.position.longitude ? minLng : location.position.longitude;
      maxLng = maxLng > location.position.longitude ? maxLng : location.position.longitude;
    }

    // Calculate center of all positions
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final centerPoint = LatLng(centerLat, centerLng);

    // Calculate the maximum distance from center to any corner of the bounding box
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;

    // Use the larger dimension to determine zoom
    // This ensures all users fit in view
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    // Calculate zoom based on the span of all users
    double zoomLevel;
    if (maxDiff < 0.01) {
      zoomLevel = 14.0; // Very close together - neighborhood
    } else if (maxDiff < 0.05) {
      zoomLevel = 12.0; // City area
    } else if (maxDiff < 0.1) {
      zoomLevel = 10.0; // Metro area
    } else if (maxDiff < 0.5) {
      zoomLevel = 8.0; // Multi-city region
    } else if (maxDiff < 2.0) {
      zoomLevel = 6.0; // State-sized area
    } else if (maxDiff < 10.0) {
      zoomLevel = 4.5; // Multi-state / small country
    } else if (maxDiff < 30.0) {
      zoomLevel = 3.5; // Country-sized (like USA coast to coast)
    } else if (maxDiff < 60.0) {
      zoomLevel = 2.5; // Continental
    } else {
      zoomLevel = 2.0; // Intercontinental
    }

    // Cap zoom at country level for faster loading (3.5 for full USA view)
    if (zoomLevel > 3.5) {
      zoomLevel = 3.5; // Show full country even if users are closer
    }

    print('[SmartZoom] Calculated zoom: $zoomLevel for span: $maxDiff degrees');
    return MapZoomResult(zoom: zoomLevel, center: centerPoint);
  }

  void _onMarkerTap(String userId, LatLng position) async {
    // Update map state with selected user
    context.read<MapBloc>().add(MapMoveToUser(userId));
    
    // Fetch user display name
    String displayName = userId.split(':')[0].replaceFirst('@', ''); // Default fallback
    try {
      final user = await userRepository?.getUserById(userId);
      if (user != null && user.displayName != null && user.displayName!.isNotEmpty) {
        displayName = user.displayName!;
      }
    } catch (e) {
    }
    
    setState(() {
      _selectedUserId = userId;
      _bubblePosition = position;
      _selectedUserName = displayName;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Always show the map UI immediately - no loading screen
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    // Don't pre-calculate - let onMapReady handle it

    return BlocListener<MapBloc, MapState>(
      listenWhen: (previous, current) =>
      (previous.moveCount != current.moveCount && current.center != null) ||
      (previous.userLocations.length != current.userLocations.length) ||
      (previous.center != current.center || previous.zoom != current.zoom),
      listener: (context, state) {
        // Handle map movement
        if (state.center != null && _isMapReady) {
          setState(() {
            _followUser = false;  // Turn off following when moving to new location
            _targetUserId = state.selectedUserId;
          });
          
          // Use provided zoom or default to street level
          final double targetZoom = state.zoom ?? 3.5; // Default to full country view
          
          _mapController.moveAndRotate(state.center!, targetZoom, 0);
          
          // Set timer to trigger bounce animation after map move completes
          _mapMoveTimer?.cancel();
          _mapMoveTimer = Timer(const Duration(milliseconds: 500), () {
            if (_targetUserId != null && mounted) {
              // Trigger a state update to force bounce animation
              setState(() {});
            }
          });
        }
        
        // Handle zoom adjustment when user locations arrive from sync (after initial zoom)
        // Only adjust if we've already done initial zoom and now have contacts
        if (_initialZoomCalculated && _isMapReady && _locationManager?.currentLatLng != null && state.userLocations.isNotEmpty) {
          // Check if this is the first time we're getting user locations
          final previousEmpty = _lastKnownUserLocationsCount == 0;
          _lastKnownUserLocationsCount = state.userLocations.length;
          
          if (previousEmpty) {
            // Smoothly adjust to include contacts
            final result = _calculateOptimalZoomAndCenter(
              _locationManager!.currentLatLng!, 
              state.userLocations
            );
            _zoom = result.zoom;
            print('[SMART ZOOM] Contacts loaded from sync, smoothly adjusting view');
            _mapController.moveAndRotate(result.center, _zoom, 0);
          }
        } else if (!_initialZoomCalculated) {
        }
      },
      child: Scaffold(
            body: Stack(
              children: [
                SizedBox(
                    height: MediaQuery.of(context).size.height * 3/4,
                child: GestureDetector(
                  onLongPressStart: (details) {
                    print('[DEBUG] GestureDetector long press at: ${details.globalPosition}');
                    
                    // Convert screen position to lat/lng
                    final renderBox = context.findRenderObject() as RenderBox?;
                    if (renderBox != null && _mapController.camera.center != null) {
                      final localPosition = renderBox.globalToLocal(details.globalPosition);
                      
                      // Check if we're in groups subscreen and have a selected group
                      final selectedSubscreen = context.read<SelectedSubscreenProvider>().selectedSubscreen;
                      
                      print('[DEBUG] Selected subscreen: $selectedSubscreen');
                      
                      // Check if the subscreen starts with "group:" which means a group is selected
                      if (selectedSubscreen.startsWith('group:')) {
                        // Extract the group ID (remove "group:" prefix)
                        final groupId = selectedSubscreen.substring(6);
                        print('[DEBUG] Showing icon wheel for group: $groupId');
                        
                        // Show icon selection wheel
                        setState(() {
                          _showIconWheel = true;
                          _iconWheelPosition = details.globalPosition;
                          // For now, use map center as location (we'll improve this later)
                          _longPressLocation = _mapController.camera.center;
                          _selectedGroupId = groupId;
                        });
                      } else {
                        print('[DEBUG] Not in group view - subscreen: $selectedSubscreen');
                      }
                    }
                  },
                  child: FlutterMap(
                  key: _mapKey,
                  mapController: _mapController,
                  options: MapOptions(
                    onTap: (tapPosition, latLng) async {
                      // Check if we're in move mode
                      if (_isMovingIcon && _movingIcon != null) {
                        // Only allow moving if user created it
                        if (_movingIcon!.creatorId != context.read<Client>().userID) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('You can only move icons you created'),
                              backgroundColor: Theme.of(context).colorScheme.error,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          setState(() {
                            _isMovingIcon = false;
                            _movingIcon = null;
                            _selectedMapIcon = null;
                            _selectedIconPosition = null;
                          });
                          return;
                        }
                        
                        // Update the icon position
                        final updatedIcon = MapIcon(
                          id: _movingIcon!.id,
                          roomId: _movingIcon!.roomId,
                          creatorId: _movingIcon!.creatorId,
                          latitude: latLng.latitude,
                          longitude: latLng.longitude,
                          iconType: _movingIcon!.iconType,
                          iconData: _movingIcon!.iconData,
                          name: _movingIcon!.name,
                          description: _movingIcon!.description,
                          createdAt: _movingIcon!.createdAt,
                          expiresAt: _movingIcon!.expiresAt,
                          metadata: _movingIcon!.metadata,
                        );
                        
                        await _mapIconRepository?.updateMapIcon(updatedIcon);
                        
                        // Send update to other users
                        await _mapIconSyncService?.sendIconUpdate(_movingIcon!.roomId, updatedIcon);
                        
                        // Notify the BLoC about the update
                        context.read<MapIconsBloc>().add(MapIconUpdated(updatedIcon));
                        
                        setState(() {
                          // Exit move mode
                          _isMovingIcon = false;
                          _movingIcon = null;
                          _selectedMapIcon = null;
                          _selectedIconPosition = null;
                        });
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Icon moved'),
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      } else {
                        // Clear selection when tapping on map
                        context.read<MapBloc>().add(MapClearSelection());
                        // Also clear bubbles if shown
                        setState(() {
                          _bubblePosition = null;
                          _selectedUserId = null;
                          _selectedUserName = null;
                          _selectedMapIcon = null;
                          _selectedIconPosition = null;
                          _showIconActionWheel = false;
                          _iconActionWheelPosition = null;
                        });
                      }
                    },
                    onLongPress: (tapPosition, latLng) {
                      print('[DEBUG] Long press detected at: $latLng');
                      
                      // Check if we're in groups subscreen and have a selected group
                      final selectedSubscreen = context.read<SelectedSubscreenProvider>().selectedSubscreen;
                      
                      print('[DEBUG] Selected subscreen: $selectedSubscreen');
                      
                      // Check if the subscreen starts with "group:" which means a group is selected
                      if (selectedSubscreen.startsWith('group:')) {
                        // Extract the group ID (remove "group:" prefix)
                        final groupId = selectedSubscreen.substring(6);
                        print('[DEBUG] Showing icon wheel for group: $groupId');
                        
                        // Show icon selection wheel
                        setState(() {
                          _showIconWheel = true;
                          _iconWheelPosition = Offset(tapPosition.global.dx, tapPosition.global.dy);
                          _longPressLocation = latLng;
                          _selectedGroupId = groupId;
                        });
                      } else {
                        print('[DEBUG] Not in group view - subscreen: $selectedSubscreen');
                      }
                    },
                    onPositionChanged: (position, hasGesture) {
                      if (hasGesture && _followUser) {
                        setState(() {
                          _followUser = false;
                        });
                      }
                      // Track map rotation changes
                      if (position.rotation != _currentMapRotation) {
                        setState(() {
                          _currentMapRotation = position.rotation ?? 0.0;
                        });
                      }

                      // Check if we've moved away from reset view
                      if (_resetCenter != null && _resetZoom != null && hasGesture) {
                        final distance = const Distance().as(
                          LengthUnit.Meter,
                          _resetCenter!,
                          position.center!,
                        );

                        // Consider moved if more than 100m away or zoom changed by more than 0.5
                        final zoomDiff = (position.zoom - _resetZoom!).abs();
                        final hasMoved = distance > 100 || zoomDiff > 0.5;

                        if (_isAtResetView != !hasMoved) {
                          setState(() {
                            _isAtResetView = !hasMoved;
                          });
                        }
                      }
                    },
                    initialCenter: _locationManager?.currentLatLng ?? LatLng(37.7749, -122.4194), // SF instead of London
                    initialZoom: _zoom,
                    initialRotation: 0.0,
                    minZoom: 3.5, // Prevent zooming out too far (country level minimum)
                    maxZoom: 17, // Prevent zooming in too close where tiles don't exist
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                      enableMultiFingerGestureRace: true,
                    ),
                    // Add camera constraints to prevent panning beyond world bounds
                    cameraConstraint: CameraConstraint.contain(
                      bounds: LatLngBounds(
                        const LatLng(-85, -180), // Southwest corner of the world
                        const LatLng(85, 180),   // Northeast corner of the world
                      ),
                    ),
                    onMapReady: () {
                      print('[SMART ZOOM] Map is ready!');
                      setState(() => _isMapReady = true);
                      
                      // Force tile loading by slightly moving the map
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (mounted && _mapController.camera.center != null) {
                          // Tiny movement to trigger tile loading
                          final currentCenter = _mapController.camera.center;
                          _mapController.move(
                            LatLng(
                              currentCenter.latitude + 0.00001,
                              currentCenter.longitude + 0.00001,
                            ),
                            _mapController.camera.zoom,
                          );
                          // Move back immediately
                          _mapController.move(currentCenter, _mapController.camera.zoom);
                        }
                      });
                      
                      // Calculate optimal zoom when map is ready
                      if (!_initialZoomCalculated) {
                        // Try to get current position if we don't have it yet
                        if (_locationManager?.currentLatLng == null) {
                          print('[SMART ZOOM] No location yet, requesting current position...');
                          _locationManager?.grabLocationAndPing().then((_) {
                            print('[SMART ZOOM] Got location: ${_locationManager?.currentLatLng}');
                            if (_locationManager?.currentLatLng != null && mounted) {
                              // Immediately center on user's location first
                              _zoom = 3.5; // Full country view for faster tile loading
                              _mapController.moveAndRotate(_locationManager!.currentLatLng!, _zoom, 0);
                              
                              // Then check if we have user locations from sync
                              final mapBloc = context.read<MapBloc>();
                              final userLocations = mapBloc.state.userLocations;
                              if (userLocations.isNotEmpty) {
                                // Recalculate with user locations
                                final result = _calculateOptimalZoomAndCenter(
                                  _locationManager!.currentLatLng!, 
                                  userLocations
                                );
                                _zoom = result.zoom;
                                print('[SMART ZOOM] Adjusting to include contacts with zoom: $_zoom');
                                _mapController.moveAndRotate(result.center, _zoom, 0);
                              }
                              setState(() {
                                _initialZoomCalculated = true;
                              });
                            }
                          });
                        } else {
                          // We already have location - immediately center on user
                          print('[SMART ZOOM] Have location: ${_locationManager?.currentLatLng}');
                          _zoom = 3.5; // Full country view for faster tile loading
                          _mapController.moveAndRotate(_locationManager!.currentLatLng!, _zoom, 0);
                          
                          // Then check if we have user locations from sync
                          final mapBloc = context.read<MapBloc>();
                          final userLocations = mapBloc.state.userLocations;
                          if (userLocations.isNotEmpty) {
                            // Recalculate with user locations
                            final result = _calculateOptimalZoomAndCenter(
                              _locationManager!.currentLatLng!, 
                              userLocations
                            );
                            _zoom = result.zoom;
                            print('[SMART ZOOM] Adjusting to include contacts with zoom: $_zoom');
                            _mapController.moveAndRotate(result.center, _zoom, 0);
                          }
                          setState(() {
                            _initialZoomCalculated = true;
                          });
                        }
                      }
                    },
                  ),
              children: [
                // Show a subtle gray placeholder while tiles are loading or style not yet determined
                // This gives instant visual feedback like Google Maps
                if (_currentMapStyle == null || _tileProvider == null || (_currentMapStyle == 'satellite' && _satelliteMapToken == null))
                  Container(
                    color: isDarkMode
                      ? const Color(0xFF2C2C2C)  // Slightly lighter dark gray for visibility
                      : const Color(0xFFE8E8E8), // Light gray for light mode
                  ),
                // Regular map tiles
                if (_currentMapStyle == 'base' && _tileProvider != null)
                  VectorTileLayer(
                    theme: _mapTheme,
                    tileProviders: TileProviders({'protomaps': _tileProvider!}),
                    fileCacheTtl: const Duration(days: 14),
                    memoryTileDataCacheMaxSize: 80,
                    memoryTileCacheMaxSize: 100,
                    concurrency: 5,
                  )
                else if (_currentMapStyle == 'satellite' && _satelliteMapToken != null)
                  TileLayer(
                    urlTemplate: '${dotenv.env['SAT_MAPS_URL'] ?? 'https://sat-maps.mygrid.app'}/tiles/alidade_satellite/{z}/{x}/{y}.png',
                    tileProvider: NetworkTileProvider(
                      headers: {
                        'Authorization': 'Bearer $_satelliteMapToken',
                      },
                    ),
                    maxZoom: 20,
                    maxNativeZoom: 20,
                    tileSize: 256,
                    errorTileCallback: (tile, error, stack) {
                      // Handle 401/403 errors indicating token issues
                      if (error.toString().contains('401') || error.toString().contains('403')) {
                        print('Satellite tile auth error: $error');
                        // Refresh token on next frame to avoid setState during build
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _refreshSatelliteTokenIfNeeded();
                        });
                      }
                    },
                  ),
                CurrentLocationLayer(
                  alignPositionOnUpdate: _followUser ? AlignOnUpdate.always : AlignOnUpdate.never,
                  style: const LocationMarkerStyle(),
                ),
                BlocBuilder<MapBloc, MapState>(
                  buildWhen: (previous, current) => 
                      previous.userLocations != current.userLocations ||
                      previous.selectedUserId != current.selectedUserId,
                  builder: (context, state) {
                    return MarkerLayer(
                      markers: state.userLocations.map((userLocation) =>
                          Marker(
                            width: 100.0,
                            height: 100.0,
                            point: userLocation.position,
                            child: GestureDetector(
                              onTap: () => _onMarkerTap(userLocation.userId, userLocation.position),
                              child: UserMapMarker(
                                userId: userLocation.userId,
                                isSelected: state.selectedUserId == userLocation.userId,
                                timestamp: userLocation.timestamp,
                              ),
                            ),
                          )
                      ).toList(),
                    );
                  },
                ),
                // Map icons layer
                BlocBuilder<MapIconsBloc, MapIconsState>(
                  builder: (context, mapIconsState) {
                    return MarkerLayer(
                      markers: mapIconsState.filteredIcons.map((icon) =>
                        Marker(
                          width: 50.0,
                          height: 50.0,
                          point: icon.position,
                          child: GestureDetector(
                            onTap: () {
                              // Show icon action wheel
                              setState(() {
                                _selectedMapIcon = icon;
                                _selectedIconPosition = icon.position;
                                _showIconActionWheel = true;
                                // Calculate screen position for the wheel
                                final renderBox = context.findRenderObject() as RenderBox;
                                final screenPoint = _mapController.camera.latLngToScreenPoint(icon.position);
                                _iconActionWheelPosition = Offset(screenPoint.x, screenPoint.y);
                                // Clear user selection when selecting an icon
                                _bubblePosition = null;
                                _selectedUserId = null;
                                _selectedUserName = null;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.shadow.withOpacity(0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  _getIconDataForType(icon.iconData),
                                  size: 24,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        )
                      ).toList(),
                    );
                  },
                ),
              ],
            ),
            )),  // Close GestureDetector and SizedBox

            if (_bubblePosition != null && _selectedUserId != null)
              UserInfoBubble(
                userId: _selectedUserId!,
                userName: _selectedUserName!,
                position: _bubblePosition!,
                onClose: () {
                  setState(() {
                    _bubblePosition = null;
                    _selectedUserId = null;
                    _selectedUserName = null;
                  });
                },
              ),
            
            // Icon action wheel
            if (_showIconActionWheel && _iconActionWheelPosition != null && _selectedMapIcon != null)
              IconActionWheel(
                position: _iconActionWheelPosition!,
                onDetails: () {
                  // Close the action wheel and show info bubble
                  setState(() {
                    _showIconActionWheel = false;
                    _iconActionWheelPosition = null;
                  });
                  // Show the info bubble after a brief delay
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) {
                      setState(() {
                        // The selected icon is already set, just trigger rebuild
                      });
                    }
                  });
                },
                onDelete: () async {
                  // Only allow delete if user created it
                  if (_selectedMapIcon!.creatorId != context.read<Client>().userID) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('You can only delete icons you created'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    setState(() {
                      _showIconActionWheel = false;
                      _iconActionWheelPosition = null;
                      _selectedMapIcon = null;
                      _selectedIconPosition = null;
                    });
                    return;
                  }
                  
                  // Show delete confirmation
                  final shouldDelete = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) {
                      final colorScheme = Theme.of(context).colorScheme;
                      
                      return Dialog(
                        backgroundColor: Colors.transparent,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: colorScheme.error.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.delete_outline,
                                    color: colorScheme.error,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Delete Icon?',
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'This icon will be permanently removed from the map.',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(0.8),
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: colorScheme.onSurface,
                                          side: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text('Cancel'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => Navigator.of(context).pop(true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colorScheme.error,
                                          foregroundColor: colorScheme.onError,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: 0,
                                        ),
                                        child: const Text('Delete'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                  
                  if (shouldDelete == true) {
                    final iconIdToDelete = _selectedMapIcon!.id;
                    final iconRoomId = _selectedMapIcon!.roomId;
                    final iconCreatorId = _selectedMapIcon!.creatorId;
                    
                    // Delete locally
                    await _mapIconRepository?.deleteMapIcon(iconIdToDelete);
                    
                    // Send delete event to other users
                    await _mapIconSyncService?.sendIconDelete(iconRoomId, iconIdToDelete, iconCreatorId);
                    
                    // Notify the BLoC about the deletion
                    context.read<MapIconsBloc>().add(MapIconDeleted(iconId: iconIdToDelete, roomId: iconRoomId));
                    
                    setState(() {
                      _showIconActionWheel = false;
                      _iconActionWheelPosition = null;
                      _selectedMapIcon = null;
                      _selectedIconPosition = null;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Icon deleted'),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } else {
                    setState(() {
                      _showIconActionWheel = false;
                      _iconActionWheelPosition = null;
                      _selectedMapIcon = null;
                      _selectedIconPosition = null;
                    });
                  }
                },
                onZoom: () {
                  // Zoom to the icon
                  if (_selectedMapIcon != null) {
                    _mapController.moveAndRotate(_selectedMapIcon!.position, 16, 0);
                  }
                  setState(() {
                    _showIconActionWheel = false;
                    _iconActionWheelPosition = null;
                    _selectedMapIcon = null;
                    _selectedIconPosition = null;
                  });
                },
                onMove: () {
                  // Enter move mode
                  setState(() {
                    _isMovingIcon = true;
                    _movingIcon = _selectedMapIcon;
                    _showIconActionWheel = false;
                    _iconActionWheelPosition = null;
                    // Clear selected icon to prevent info bubble from showing
                    _selectedMapIcon = null;
                    _selectedIconPosition = null;
                  });
                },
                onCancel: () {
                  setState(() {
                    _showIconActionWheel = false;
                    _iconActionWheelPosition = null;
                    _selectedMapIcon = null;
                    _selectedIconPosition = null;
                  });
                },
              ),
            
            // Map icon info bubble (shown when details is pressed)
            if (_selectedMapIcon != null && _selectedIconPosition != null && !_showIconActionWheel)
              MapIconInfoBubble(
                icon: _selectedMapIcon!,
                position: _selectedIconPosition!,
                creatorName: _selectedMapIcon!.creatorId == context.read<Client>().userID 
                  ? 'You' 
                  : null, // We can fetch the actual name later
                onClose: () {
                  setState(() {
                    _selectedMapIcon = null;
                    _selectedIconPosition = null;
                    _isEditingIconDescription = false;
                  });
                },
                onEditingChanged: (isEditing) {
                  setState(() {
                    _isEditingIconDescription = isEditing;
                  });
                },
                onUpdate: _selectedMapIcon!.creatorId == context.read<Client>().userID
                  ? (name, description) async {
                      // Update the icon if it's created by the current user
                      final updatedIcon = MapIcon(
                        id: _selectedMapIcon!.id,
                        roomId: _selectedMapIcon!.roomId,
                        creatorId: _selectedMapIcon!.creatorId,
                        latitude: _selectedMapIcon!.latitude,
                        longitude: _selectedMapIcon!.longitude,
                        iconType: _selectedMapIcon!.iconType,
                        iconData: _selectedMapIcon!.iconData,
                        name: name,
                        description: description,
                        createdAt: _selectedMapIcon!.createdAt,
                        expiresAt: _selectedMapIcon!.expiresAt,
                        metadata: _selectedMapIcon!.metadata,
                      );
                      
                      await _mapIconRepository?.updateMapIcon(updatedIcon);
                      
                      // Send update to other users
                      await _mapIconSyncService?.sendIconUpdate(updatedIcon.roomId, updatedIcon);
                      
                      // Notify the BLoC about the update
                      context.read<MapIconsBloc>().add(MapIconUpdated(updatedIcon));
                      
                      setState(() {
                        // Update the selected icon
                        _selectedMapIcon = updatedIcon;
                      });
                    }
                  : null,
                onDelete: null, // Delete is handled by the action wheel now
              ),
            
            // Move mode banner
            if (_isMovingIcon)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.touch_app,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tap anywhere to move the icon',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isMovingIcon = false;
                            _movingIcon = null;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Positioned(
              top: 100,
              left: 16,
              child: FloatingActionButton(
                heroTag: "settingsBtn",
                backgroundColor: isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SettingsPage()),
                  );
                },
                child: Icon(
                    Icons.menu,
                    color: isDarkMode ? colorScheme.primary : Colors.black
                ),
                mini: true,
              ),
            ),

            Positioned(
              right: 16,
              top: 100,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCompassButton(isDarkMode, colorScheme),
                  const SizedBox(height: 10),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      FloatingActionButton(
                        heroTag: "pingBtn",
                        backgroundColor: _isPingOnCooldown
                            ? Colors.grey
                            : (isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8)),
                        onPressed: _isPingOnCooldown ? null : _sendPing,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_isPingOnCooldown)
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  value: _pingCooldownSeconds / 5,
                                  strokeWidth: 2,
                                  color: isDarkMode ? colorScheme.primary : Colors.black,
                                  backgroundColor: isDarkMode ? colorScheme.surfaceVariant : Colors.grey.withOpacity(0.3),
                                ),
                              )
                            else
                              Icon(
                                Icons.sensors,
                                color: isDarkMode ? colorScheme.primary : Colors.black,
                                size: 24,
                              ),
                            if (_isPingOnCooldown)
                              Text(
                                '$_pingCooldownSeconds',
                                style: TextStyle(
                                  color: isDarkMode ? colorScheme.primary : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                        mini: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!utils.isCustomHomeserver(_roomService?.getMyHomeserver() ?? ''))
                    FloatingActionButton(
                      heroTag: "mapSelectorBtn",
                      backgroundColor: isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8),
                      onPressed: () {
                        setState(() {
                          _showMapSelector = !_showMapSelector;
                        });
                      },
                      child: Icon(
                        Icons.layers,
                        color: isDarkMode ? colorScheme.primary : Colors.black,
                        size: 24,
                      ),
                      mini: true,
                    ),
                  const SizedBox(height: 10),
                  // Center on user button
                  FloatingActionButton(
                    heroTag: 'center_on_user_fab',
                    backgroundColor: _followUser
                      ? colorScheme.primary
                      : (isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8)),
                    onPressed: () {
                      // Center on user with same zoom level as other users
                      _mapController.move(_locationManager?.currentLatLng ?? _mapController.camera.center, 16.0);
                      setState(() {
                        _followUser = true;
                        _isAtResetView = false;  // Unhighlight globe when centering on user
                      });
                    },
                    child: Icon(
                      Icons.my_location,
                      color: _followUser
                        ? Colors.white
                        : (isDarkMode ? colorScheme.primary : Colors.black),
                    ),
                    tooltip: 'Center on me',
                    elevation: _followUser ? 6 : 2,
                    mini: true,
                  ),
                  const SizedBox(height: 10),
                  // Globe reset button
                  FloatingActionButton(
                    heroTag: 'reset_view_fab',
                    backgroundColor: _isAtResetView
                      ? colorScheme.primary
                      : (isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8)),
                    onPressed: _resetToInitialZoom,
                    child: Icon(
                      Icons.public,
                      color: _isAtResetView
                        ? Colors.white
                        : (isDarkMode ? colorScheme.primary : Colors.black),
                    ),
                    tooltip: 'Reset view',
                    elevation: _isAtResetView ? 6 : 2,
                    mini: true,
                  ),
                ],
              ),
            ),

            // Map Selector Overlay (only for default homeserver)
            if (_showMapSelector && !utils.isCustomHomeserver(_roomService?.getMyHomeserver() ?? ''))
              Positioned(
                top: 300,
                right: 16,
                child: _buildMapSelector(isDarkMode, colorScheme),
              ),
              
            Align(
              alignment: Alignment.bottomCenter,
              child: MapScrollWindow(
                isEditingMapIcon: _isEditingIconDescription,
              ),
            ),
            
            // Icon selection wheel overlay
            if (_showIconWheel && _iconWheelPosition != null)
              IconSelectionWheel(
                position: _iconWheelPosition!,
                onIconSelected: (iconType) {
                  // Handle icon selection
                  _handleIconSelection(iconType);
                },
                onCancel: () {
                  setState(() {
                    _showIconWheel = false;
                    _iconWheelPosition = null;
                    _longPressLocation = null;
                    _selectedGroupId = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  IconData _getIconDataForType(String iconType) {
    switch (iconType) {
      case 'pin':
        return Icons.location_on;
      case 'warning':
        return Icons.warning;
      case 'food':
        return Icons.restaurant;
      case 'car':
        return Icons.directions_car;
      case 'home':
        return Icons.home;
      case 'star':
        return Icons.star;
      case 'heart':
        return Icons.favorite;
      case 'flag':
        return Icons.flag;
      default:
        return Icons.place;
    }
  }
  
  Widget _buildCompassButton(bool isDarkMode, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () {
        // Orient north when tapped
        _mapController.moveAndRotate(
          _mapController.camera.center,
          _mapController.camera.zoom,
          0, // Set rotation to 0 (north)
        );
        setState(() {
          _currentMapRotation = 0.0;
        });
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Compass circle background
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDarkMode ? colorScheme.outline.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
                  width: 1,
                ),
              ),
            ),
            // Rotating compass needle
            Transform.rotate(
              angle: _currentMapRotation * (3.141592653589793 / 180), // Convert degrees to radians
              child: CustomPaint(
                size: Size(28, 28),
                painter: CompassPainter(
                  northColor: Colors.red,
                  southColor: isDarkMode ? colorScheme.onSurface.withOpacity(0.6) : Colors.black.withOpacity(0.6),
                ),
              ),
            ),
            // North indicator (N)
            Positioned(
              top: 4,
              child: Text(
                'N',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? colorScheme.primary : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Subtle loading indicator
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  colorScheme.primary.withOpacity(0.7),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMapSelector(bool isDarkMode, ColorScheme colorScheme) {
    return Container(
      width: 220,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with title and close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Map Layers',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showMapSelector = false;
                  });
                },
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),

          // Loading overlay if switching maps
          if (_isLoadingMapStyle)
            Container(
              height: 120,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                      strokeWidth: 2,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Loading map...',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Base Map Option
            _buildMapOption(
              title: 'Standard Map',
              imagePath: 'assets/extras/basemaps.png',
              isSelected: _currentMapStyle == 'base',
              onTap: _isLoadingMapStyle ? null : () {
                _selectMapStyle('base');
              },
              colorScheme: colorScheme,
              isDarkMode: isDarkMode,
            ),
            SizedBox(height: 8),
            // Satellite Map Option
            _buildMapOption(
              title: 'Satellite Map',
              imagePath: 'assets/extras/satellite.png',
              isSelected: _currentMapStyle == 'satellite',
              showStar: true,
              onTap: _isLoadingMapStyle ? null : () async {
                final hasSubscription = await _subscriptionService.hasActiveSubscription();
                if (!hasSubscription) {
                  // Navigate to subscription page
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SubscriptionScreen()),
                  );
                } else {
                  _selectMapStyle('satellite');
                }
              },
              colorScheme: colorScheme,
              isDarkMode: isDarkMode,
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildMapOption({
    required String title,
    required String imagePath,
    required bool isSelected,
    required VoidCallback? onTap,
    required ColorScheme colorScheme,
    required bool isDarkMode,
    bool showStar = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180, // Fixed width for consistent alignment
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected 
              ? colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? colorScheme.primary 
                : colorScheme.outline.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Map preview image
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected 
                      ? colorScheme.primary 
                      : (isDarkMode ? Colors.white : Colors.black),
                ),
              ),
            ),
            if (showStar)
              Icon(
                Icons.star,
                color: Colors.amber,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _selectMapStyle(String style) async {
    // Don't allow switching if already loading
    if (_isLoadingMapStyle) return;

    // Don't switch if already on the selected style
    if (_currentMapStyle == style) return;

    setState(() {
      _isLoadingMapStyle = true;
    });

    try {
      if (style == 'satellite') {
        // Check subscription and get token
        final hasSubscription = await _subscriptionService.hasActiveSubscription();
        if (!hasSubscription) {
          setState(() {
            _isLoadingMapStyle = false;
          });
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SubscriptionScreen()),
          );
          return;
        }

        // Try to get a map token (will use cached if valid)
        final token = await _subscriptionService.getMapToken();
        if (token == null) {
          setState(() {
            _isLoadingMapStyle = false;
          });
          // Failed to get token, navigate to subscription page
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SubscriptionScreen()),
        );
        return;
      }
      
      // Switch to satellite tile provider with token
      print('Got satellite map token: ${token.substring(0, 20)}...'); // Debug log
      print('Full token length: ${token.length}'); // Debug log
      setState(() {
        _satelliteMapToken = token;
        _currentMapStyle = style;
        _showMapSelector = false;
        _isLoadingMapStyle = false;
      });
      
      // Save the preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_mapStyleKey, style);
      
      // Force a rebuild to ensure new token is used
      if (mounted) {
        setState(() {});
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to satellite maps'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } else {
      // Switch to base maps
      setState(() {
        _currentMapStyle = style;
        _showMapSelector = false;
        _satelliteMapToken = null; // Clear token when switching back
        _isLoadingMapStyle = false;
      });
      
      // Save the preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_mapStyleKey, style);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to base maps'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
    } catch (e) {
      // Handle any errors and reset loading state
      print('Error switching map style: $e');
      setState(() {
        _isLoadingMapStyle = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to switch map layer'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }
}

class CompassPainter extends CustomPainter {
  final Color northColor;
  final Color southColor;

  CompassPainter({
    required this.northColor,
    required this.southColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint northPaint = Paint()
      ..color = northColor
      ..style = PaintingStyle.fill;

    final Paint southPaint = Paint()
      ..color = southColor
      ..style = PaintingStyle.fill;

    final double centerX = size.width / 2;
    final double centerY = size.height / 2;

    // North arrow (red) - using ui.Path to avoid conflict with latlong2.Path
    final ui.Path northPath = ui.Path();
    northPath.moveTo(centerX, centerY - 10); // Top point
    northPath.lineTo(centerX - 3, centerY); // Left point
    northPath.lineTo(centerX + 3, centerY); // Right point
    northPath.close();

    // South arrow (gray)
    final ui.Path southPath = ui.Path();
    southPath.moveTo(centerX, centerY + 10); // Bottom point
    southPath.lineTo(centerX - 3, centerY); // Left point
    southPath.lineTo(centerX + 3, centerY); // Right point
    southPath.close();

    canvas.drawPath(northPath, northPaint);
    canvas.drawPath(southPath, southPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

