import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import 'grid_map_style.dart';
import 'maplibre_camera_facade.dart';

import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/blocs/invitations/invitations_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_state.dart';

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
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/services/sharing_state_notifier.dart';
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
import 'package:grid_frontend/services/passkey_service.dart';
import 'package:grid_frontend/screens/settings/passkey_management_screen.dart';

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
  final MaplibreCameraFacade _mapController = MaplibreCameraFacade();
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

  // Track if user has completed onboarding (to avoid auto-requesting location permission)
  bool _hasCompletedOnboarding = false;

  ml.MapLibreMapController? _mlController;
  String? _styleJson;
  bool _isDarkStyle = false;
  final GlobalKey _mapKeyForSize = GlobalKey();

  // Authoritative screen positions for every marker, sourced from maplibre's
  // own projection. Keyed by "lat,lng". Values are screen-pixel offsets
  // relative to the map widget's top-left. Refreshed every camera tick.
  final Map<String, Offset> _markerScreenPositions = {};
  int _projectionSeq = 0;

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

  // Saved "home" location from Settings → auto-pause feature. Null if unset.
  LatLng? _homeLocation;
  double _homeRadiusMeters = 25;

  @override
  void initState() {
    super.initState();
    print('[MapTab] Initializing - hasInitialized: $_hasInitialized');
    WidgetsBinding.instance.addObserver(this);
    _styleJson = buildGridMapStyle(dark: _isDarkStyle);

    // Load saved home location (set in Settings).
    _reloadHomeLocation();

    // Check if app was properly initialized
    _checkAndInitialize().then((_) {
      // Only access _locationManager after initialization is complete
      if (mounted) {
      }
    });
    
    // Start review manager session
    AppReviewManager.startSession();
    
    // Show onboarding modal if user hasn't seen it yet
    // Pass callback to start location tracking AFTER disclosure is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OnboardingModal.showOnboardingIfNeeded(
        context,
        onComplete: () {
          // Start location tracking after user has seen permission disclosure
          setState(() {
            _hasCompletedOnboarding = true;
          });
          _startLocationTracking();

          // Check if user needs passkey migration warning (default homeserver only)
          _checkPasskeyWarning();
        },
      ).then((_) {
        // For existing users who already completed onboarding,
        // the onComplete callback won't fire — check here instead
        if (!mounted) return;
        OnboardingModal.shouldShowOnboarding().then((shouldShow) {
          if (!shouldShow) _checkPasskeyWarning();
        });
      });

      // Schedule review prompt check for later (after user has used the app for a bit)
      _scheduleReviewPromptCheck();
    });
  }
  
  Future<void> _checkPasskeyWarning() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Only for default homeserver users
      final customHomeserver = prefs.getString('custom_homeserver');
      if (customHomeserver != null) return;

      // Don't show if dismissed today
      final lastDismissed = prefs.getString('passkey_warning_dismissed');
      if (lastDismissed != null) {
        final dismissed = DateTime.tryParse(lastDismissed);
        if (dismissed != null &&
            DateTime.now().difference(dismissed).inHours < 24) {
          return;
        }
      }

      // Check if user has any passkeys
      final jwt = prefs.getString('loginToken');
      if (jwt == null) return;

      final passkeyService = PasskeyService();
      final passkeys = await passkeyService.listPasskeys(jwt);
      if (passkeys.isNotEmpty) return;

      if (!mounted) return;

      final colorScheme = Theme.of(context).colorScheme;
      showDialog(
        context: context,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              decoration: BoxDecoration(
                color: colorScheme.background,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.05),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: colorScheme.outline.withOpacity(0.1),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SMS Login Ending Soon',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onBackground,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Action required before June 2026',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onBackground
                                      .withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'We are phasing out SMS login by the end of May 2026. Please add a passkey to your account to keep access.',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      colorScheme.primary.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const PasskeyManagementScreen(),
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.fingerprint,
                                      color: colorScheme.onPrimary,
                                      size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Add Passkey Now',
                                    style: TextStyle(
                                      color: colorScheme.onPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setString(
                                'passkey_warning_dismissed',
                                DateTime.now().toIso8601String(),
                              );
                              Navigator.pop(context);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Remind Me Later',
                              style: TextStyle(
                                color:
                                    colorScheme.onSurface.withOpacity(0.6),
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      // Silently fail — don't block the app for a warning
      debugPrint('Passkey warning check failed: $e');
    }
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
      print('[MapTab] App launched from background/terminated state');
    }

    await _loadMapProvider();

    if (wasLaunchedFromBackground && mounted) {
      setState(() {
        print('[MapTab] UI refreshed after background launch');
      });
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

    // Check if user has completed onboarding v2 before starting location tracking
    // This ensures we show the permission disclosure BEFORE requesting permissions
    // Using v2 flag to force all users to see the new mandatory permission disclosure
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding_v2') ?? false;

    setState(() {
      _hasCompletedOnboarding = hasSeenOnboarding;
    });

    if (hasSeenOnboarding) {
      // User has already seen onboarding v2, safe to start tracking
      _startLocationTracking();
    }
    // If they haven't seen onboarding v2, tracking will start after onboarding completes
    
    // Listen for location updates to trigger zoom calculation
    _locationManager?.addListener(_onLocationUpdate);
    
    // Load avatars ONCE on init without any refresh loops
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _loadAvatarsOnce();
      }
    });
  }
  
  // Start location tracking (only called after permission disclosure/onboarding)
  Future<void> _startLocationTracking() async {
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
    _mlController?.removeListener(_onMaplibreCameraChanged);
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
    
    // Only reinitialize if app was paused for a significant time
    if (state == AppLifecycleState.resumed && _pausedTime != null) {
      final pauseDuration = DateTime.now().difference(_pausedTime!);

      if (pauseDuration.inSeconds > 5) {
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

  // Satellite mode was deprecated when map style switched to system brightness.
  // Kept as a no-op stub so any remaining callers compile.
  Future<void> _refreshSatelliteTokenIfNeeded() async {}

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
      // Ensure dotenv is loaded before proceeding.
      if (dotenv.env.isEmpty) {
        try {
          await dotenv.load(fileName: ".env");
        } catch (e) {}
      }

      // Style JSON is reactively built per-build based on system brightness;
      // nothing to pre-fetch here.
      if (mounted) {
        context.read<MapBloc>().add(MapInitialize());
        setState(() {});
      }
    } catch (e) {
      _showMapErrorDialog();
    }
  }

  Future<void> _loadMapStylePreference() async {
    // Map style is now driven by system brightness; user choice no longer
    // persisted. Kept as a stub so existing call sites still resolve.
    _currentMapStyle = 'base';
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

    // Calculate center of all positions (midpoint)
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final centerPoint = LatLng(centerLat, centerLng);

    // Calculate the maximum distance from center to any corner of the bounding box
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;

    // Use the larger dimension to determine zoom
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
      zoomLevel = 3.5;
    }

    // Estimate viewport size at this zoom level (degrees of lat/lng visible on screen)
    // These are rough approximations for a typical phone screen
    double viewportRadius;
    if (zoomLevel <= 2.0) {
      viewportRadius = 90.0; // World view - very zoomed out
    } else if (zoomLevel <= 3.5) {
      viewportRadius = 30.0; // Country view
    } else if (zoomLevel <= 6.0) {
      viewportRadius = 10.0; // State view
    } else if (zoomLevel <= 8.0) {
      viewportRadius = 2.0; // Multi-city view
    } else if (zoomLevel <= 10.0) {
      viewportRadius = 0.5; // Metro view
    } else if (zoomLevel <= 12.0) {
      viewportRadius = 0.1; // City view
    } else {
      viewportRadius = 0.02; // Neighborhood view
    }

    // Check if current user would be visible from the midpoint center
    final distanceFromCenter = ((userPosition.latitude - centerLat).abs() +
                                 (userPosition.longitude - centerLng).abs()) / 2;

    // If current user is too far from midpoint, adjust center to keep them visible
    if (distanceFromCenter > viewportRadius) {
      // Shift center toward current user to ensure they're at the edge of viewport
      final shiftFactor = (distanceFromCenter - viewportRadius) / distanceFromCenter;
      final adjustedLat = centerLat + (userPosition.latitude - centerLat) * shiftFactor;
      final adjustedLng = centerLng + (userPosition.longitude - centerLng) * shiftFactor;

      print('[SmartZoom] Adjusted center to keep current user visible');
      return MapZoomResult(zoom: zoomLevel, center: LatLng(adjustedLat, adjustedLng));
    }

    print('[SmartZoom] Calculated zoom: $zoomLevel for span: $maxDiff degrees');
    return MapZoomResult(zoom: zoomLevel, center: centerPoint);
  }

  /// "SHARING WITH N" pill rendered top-center over the map.
  ///
  /// When the user has paused sharing (incognito on), the mint glow dot
  /// is swapped for a purple dot with no glow and the label reads
  /// "SHARING PAUSED" instead of the contact count.
  Widget _buildSharingPill() {
    return BlocBuilder<MapBloc, MapState>(
      buildWhen: (p, c) => p.userLocations.length != c.userLocations.length,
      builder: (context, state) {
        final count = state.userLocations.length;
        return Consumer<SharingStateNotifier>(
          builder: (context, sharingState, _) {
            final paused = sharingState.isPaused;
            final dotColor = paused ? GridTokens.paused : GridTokens.mint;
            final textColor = paused ? GridTokens.paused : GridTokens.text;
            final label = paused ? 'SHARING PAUSED' : 'SHARING WITH $count';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: GridTokens.surface.withOpacity(0.92),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: GridTokens.hairlineStrong),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      boxShadow: paused
                          ? null
                          : [
                              BoxShadow(
                                color: GridTokens.mint.withOpacity(0.55),
                                blurRadius: 6,
                              ),
                            ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  GridMono(
                    label,
                    color: textColor,
                    size: 10.5,
                    letterSpacing: 0.1,
                    weight: FontWeight.w600,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  int _invitesBadgeCount(BuildContext context) {
    try {
      final state = context.read<InvitationsBloc>().state;
      if (state is InvitationsLoaded) return state.invitations.length;
    } catch (_) {}
    return 0;
  }

  void _onMaplibreCameraChanged() {
    if (!mounted) return;
    _mapController.syncFromController();
    // Re-position the marker overlay widgets to stay glued to the map
    // during pan/zoom gestures (not just on idle).
    setState(() {});
    _refreshMarkerScreenPositions();
  }

  String _latLngKey(LatLng p) => '${p.latitude},${p.longitude}';

  /// Ask maplibre for the authoritative screen position of every marker we
  /// render. Uses the controller's batch API (one round-trip across the
  /// platform channel for all markers). Stale results from concurrent calls
  /// are ignored via [_projectionSeq].
  Future<void> _refreshMarkerScreenPositions() async {
    final controller = _mlController;
    if (controller == null || !mounted) return;

    final userLocations = context.read<MapBloc>().state.userLocations;
    final mapIcons = context.read<MapIconsBloc>().state.filteredIcons;
    if (userLocations.isEmpty && mapIcons.isEmpty) return;

    // Collect all distinct LatLngs and remember the matching keys in order.
    final List<ml.LatLng> mlPoints = [];
    final List<String> keys = [];
    for (final u in userLocations) {
      mlPoints.add(ml.LatLng(u.position.latitude, u.position.longitude));
      keys.add(_latLngKey(u.position));
    }
    for (final i in mapIcons) {
      mlPoints.add(ml.LatLng(i.position.latitude, i.position.longitude));
      keys.add(_latLngKey(i.position));
    }

    final seq = ++_projectionSeq;
    try {
      final screenPoints = await controller.toScreenLocationBatch(mlPoints);
      // Ignore stale responses — camera may have moved past us.
      if (!mounted || seq != _projectionSeq) return;
      for (var idx = 0; idx < keys.length && idx < screenPoints.length; idx++) {
        final p = screenPoints[idx];
        _markerScreenPositions[keys[idx]] =
            Offset(p.x.toDouble(), p.y.toDouble());
      }
      setState(() {});
    } catch (_) {
      // toScreenLocation can race with map teardown — swallow.
    }
  }

  Offset _screenPosFor(LatLng p) =>
      _markerScreenPositions[_latLngKey(p)] ??
      _mapController.camera.latLngToScreenPoint(p);

  /// Reload the "home" location + geofence radius from SharedPreferences
  /// (keys: `home_location` = "lat,lng", `home_radius` = double meters).
  /// Called on init and after returning from Settings.
  Future<void> _reloadHomeLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('home_location');
      final radius = prefs.getDouble('home_radius') ?? 25;
      if (raw == null || raw.isEmpty) {
        if (_homeLocation != null && mounted) {
          setState(() {
            _homeLocation = null;
            _homeRadiusMeters = radius;
          });
        }
        return;
      }
      final parts = raw.split(',');
      if (parts.length != 2) return;
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat == null || lng == null) return;
      final parsed = LatLng(lat, lng);
      if (!mounted) return;
      final locChanged = _homeLocation == null ||
          _homeLocation!.latitude != parsed.latitude ||
          _homeLocation!.longitude != parsed.longitude;
      if (locChanged || _homeRadiusMeters != radius) {
        setState(() {
          _homeLocation = parsed;
          _homeRadiusMeters = radius;
        });
      }
    } catch (_) {
      // Swallow — pref-read failure shouldn't break the map.
    }
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

    // Keep map style in sync with system brightness.
    if (isDarkMode != _isDarkStyle) {
      _isDarkStyle = isDarkMode;
      _styleJson = buildGridMapStyle(dark: _isDarkStyle);
      // Hot-swap the style on an already-running map.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mlController?.setStyle(_styleJson!);
      });
    }

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
            _isAtResetView = false;  // Turn off reset view when moving to a user
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
                child: LayoutBuilder(builder: (context, constraints) {
                  _mapController.setMapSize(Size(constraints.maxWidth, constraints.maxHeight));
                  return Stack(children: [
                  ml.MapLibreMap(
                  key: _mapKey,
                  styleString: _styleJson ?? buildGridMapStyle(dark: isDarkMode),
                  initialCameraPosition: ml.CameraPosition(
                    target: ml.LatLng(
                      (_locationManager?.currentLatLng ?? LatLng(37.7749, -122.4194)).latitude,
                      (_locationManager?.currentLatLng ?? LatLng(37.7749, -122.4194)).longitude,
                    ),
                    zoom: _zoom,
                  ),
                  myLocationEnabled: _hasCompletedOnboarding,
                  myLocationTrackingMode: _followUser
                      ? ml.MyLocationTrackingMode.tracking
                      : ml.MyLocationTrackingMode.none,
                  trackCameraPosition: true,
                  minMaxZoomPreference: const ml.MinMaxZoomPreference(3.5, 17),
                  rotateGesturesEnabled: true,
                  tiltGesturesEnabled: false,
                  attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
                  onMapCreated: (controller) {
                    _mlController = controller;
                    _mapController.attach(controller);
                    controller.addListener(_onMaplibreCameraChanged);
                  },
                  onStyleLoadedCallback: () {
                    print('[SMART ZOOM] Style loaded — map ready');
                    if (mounted) setState(() => _isMapReady = true);
                    _mapController.syncFromController();

                    if (!_initialZoomCalculated) {
                      if (_locationManager?.currentLatLng == null) {
                        _locationManager?.grabLocationAndPing().then((_) {
                          if (_locationManager?.currentLatLng != null && mounted) {
                            _zoom = 3.5;
                            _mapController.moveAndRotate(_locationManager!.currentLatLng!, _zoom, 0);

                            final userLocations = context.read<MapBloc>().state.userLocations;
                            if (userLocations.isNotEmpty) {
                              final result = _calculateOptimalZoomAndCenter(
                                _locationManager!.currentLatLng!,
                                userLocations,
                              );
                              _zoom = result.zoom;
                              _mapController.moveAndRotate(result.center, _zoom, 0);
                            }
                            setState(() => _initialZoomCalculated = true);
                          }
                        });
                      } else {
                        _zoom = 3.5;
                        _mapController.moveAndRotate(_locationManager!.currentLatLng!, _zoom, 0);

                        final userLocations = context.read<MapBloc>().state.userLocations;
                        if (userLocations.isNotEmpty) {
                          final result = _calculateOptimalZoomAndCenter(
                            _locationManager!.currentLatLng!,
                            userLocations,
                          );
                          _zoom = result.zoom;
                          _mapController.moveAndRotate(result.center, _zoom, 0);
                        }
                        setState(() => _initialZoomCalculated = true);
                      }
                    }
                  },
                  onMapClick: (point, latLng) async {
                    final dartLatLng = LatLng(latLng.latitude, latLng.longitude);
                    if (_isMovingIcon && _movingIcon != null) {
                      if (_movingIcon!.creatorId != context.read<Client>().userID) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('You can only move icons you created'),
                            backgroundColor: Theme.of(context).colorScheme.error,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

                      final updatedIcon = MapIcon(
                        id: _movingIcon!.id,
                        roomId: _movingIcon!.roomId,
                        creatorId: _movingIcon!.creatorId,
                        latitude: dartLatLng.latitude,
                        longitude: dartLatLng.longitude,
                        iconType: _movingIcon!.iconType,
                        iconData: _movingIcon!.iconData,
                        name: _movingIcon!.name,
                        description: _movingIcon!.description,
                        createdAt: _movingIcon!.createdAt,
                        expiresAt: _movingIcon!.expiresAt,
                        metadata: _movingIcon!.metadata,
                      );

                      await _mapIconRepository?.updateMapIcon(updatedIcon);
                      await _mapIconSyncService?.sendIconUpdate(_movingIcon!.roomId, updatedIcon);
                      context.read<MapIconsBloc>().add(MapIconUpdated(updatedIcon));

                      setState(() {
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    } else {
                      context.read<MapBloc>().add(MapClearSelection());
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
                  onMapLongClick: (point, latLng) {
                    final dartLatLng = LatLng(latLng.latitude, latLng.longitude);
                    final selectedSubscreen = context.read<SelectedSubscreenProvider>().selectedSubscreen;
                    if (selectedSubscreen.startsWith('group:')) {
                      final groupId = selectedSubscreen.substring(6);
                      setState(() {
                        _showIconWheel = true;
                        _iconWheelPosition = Offset(point.x.toDouble(), point.y.toDouble());
                        _longPressLocation = dartLatLng;
                        _selectedGroupId = groupId;
                      });
                    }
                  },
                  onCameraIdle: () {
                    _mapController.syncFromController();
                    final cam = _mapController.camera;
                    if (cam.center == null) return;
                    if (cam.bearing != _currentMapRotation) {
                      setState(() => _currentMapRotation = cam.bearing);
                    }
                    if (_resetCenter != null && _resetZoom != null) {
                      final distance = const Distance().as(
                        LengthUnit.Meter,
                        _resetCenter!,
                        cam.center!,
                      );
                      final zoomDiff = (cam.zoom - _resetZoom!).abs();
                      if (_isAtResetView && (distance > 100 || zoomDiff > 0.5)) {
                        setState(() => _isAtResetView = false);
                      }
                    }
                    // force refresh of marker overlay positions
                    if (mounted) setState(() {});
                  },
                  onCameraTrackingDismissed: () {
                    if (_followUser) setState(() => _followUser = false);
                  },
                ),
                // Home-location pin overlay (under user-location markers).
                Builder(
                  builder: (context) {
                    if (!_isMapReady || _homeLocation == null) {
                      return const SizedBox.shrink();
                    }
                    final home = _homeLocation!;
                    final current = _locationManager?.currentLatLng;
                    final inside = current != null &&
                        const Distance().as(
                              LengthUnit.Meter,
                              home,
                              current,
                            ) <=
                            _homeRadiusMeters;
                    final pt = _screenPosFor(home);
                    final accent = inside ? GridTokens.mint : GridTokens.amber;
                    final label = inside ? 'AT HOME' : 'HOME';

                    // Geofence radius circle in screen pixels — Web Mercator
                    // resolution at 512-pixel world tiles (matches maplibre's
                    // internal convention used elsewhere in this file).
                    final zoom = _mapController.camera.zoom;
                    final lat = home.latitude * math.pi / 180.0;
                    final metersPerPixel =
                        78271.516 * math.cos(lat) / math.pow(2, zoom);
                    final radiusPx = metersPerPixel <= 0
                        ? 0.0
                        : _homeRadiusMeters / metersPerPixel;
                    final diameter = radiusPx * 2;

                    return IgnorePointer(
                      ignoring: true,
                      child: Stack(
                        children: [
                          // Geofence radius (under the pin).
                          if (diameter > 4)
                            Positioned(
                              left: pt.dx - radiusPx,
                              top: pt.dy - radiusPx,
                              width: diameter,
                              height: diameter,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accent.withOpacity(0.12),
                                  border: Border.all(
                                    color: accent.withOpacity(0.55),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          // Pin + label.
                          Positioned(
                            left: pt.dx - 30,
                            top: pt.dy - 18,
                            width: 60,
                            height: 60,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: GridTokens.amberSoft,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: GridTokens.amber,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (inside
                                                ? GridTokens.mint
                                                : Colors.white)
                                            .withOpacity(inside ? 0.55 : 0.85),
                                        blurRadius: inside ? 12 : 6,
                                        spreadRadius: inside ? 1 : 0,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.home_rounded,
                                    size: 20,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                GridMono(
                                  label,
                                  color: accent,
                                  size: 9,
                                  letterSpacing: 0.4,
                                  weight: FontWeight.w700,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // User-location markers (Stack overlay).
                BlocBuilder<MapBloc, MapState>(
                  buildWhen: (previous, current) =>
                      previous.userLocations != current.userLocations ||
                      previous.selectedUserId != current.selectedUserId,
                  builder: (context, state) {
                    if (!_isMapReady) return const SizedBox.shrink();
                    return IgnorePointer(
                      ignoring: false,
                      child: Stack(
                        children: state.userLocations.map((userLocation) {
                          final pt = _screenPosFor(userLocation.position);
                          return Positioned(
                            left: pt.dx - 50,
                            top: pt.dy - 50,
                            width: 100,
                            height: 100,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => _onMarkerTap(userLocation.userId, userLocation.position),
                              child: UserMapMarker(
                                userId: userLocation.userId,
                                isSelected: state.selectedUserId == userLocation.userId,
                                timestamp: userLocation.timestamp,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
                // Map-icons overlay.
                BlocBuilder<MapIconsBloc, MapIconsState>(
                  builder: (context, mapIconsState) {
                    if (!_isMapReady) return const SizedBox.shrink();
                    return IgnorePointer(
                      ignoring: false,
                      child: Stack(
                        children: mapIconsState.filteredIcons.map((icon) {
                          final pt = _screenPosFor(icon.position);
                          return Positioned(
                            left: pt.dx - 25,
                            top: pt.dy - 25,
                            width: 50,
                            height: 50,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () {
                                setState(() {
                                  _selectedMapIcon = icon;
                                  _selectedIconPosition = icon.position;
                                  _showIconActionWheel = true;
                                  _iconActionWheelPosition = Offset(pt.dx, pt.dy);
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
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ]);
            })),  // close Stack, LayoutBuilder builder, LayoutBuilder, SizedBox

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
                      return Dialog(
                        backgroundColor: Colors.transparent,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.9,
                          ),
                          decoration: BoxDecoration(
                            color: GridTokens.surface,
                            borderRadius:
                                BorderRadius.circular(GridTokens.rXl),
                            border: Border.all(color: GridTokens.hairline),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: const BoxDecoration(
                                  color: GridTokens.dangerSoft,
                                  borderRadius: BorderRadius.only(
                                    topLeft:
                                        Radius.circular(GridTokens.rXl),
                                    topRight:
                                        Radius.circular(GridTokens.rXl),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: GridTokens.danger
                                            .withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(
                                            GridTokens.rMd),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.delete_outline,
                                        color: GridTokens.danger,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Delete icon',
                                            style: GoogleFonts.getFont(
                                              'Geist',
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.015,
                                              color: GridTokens.text,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "This can't be undone.",
                                            style: GoogleFonts.getFont(
                                              'Geist',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              color: GridTokens.text2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 18, 20, 0),
                                child: Text(
                                  'This icon will be permanently removed from the map.',
                                  style: GoogleFonts.getFont(
                                    'Geist',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: GridTokens.text2,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 18, 20, 20),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GridButton(
                                        label: 'Cancel',
                                        style: GridButtonStyle.secondary,
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: GridButton(
                                        label: 'Delete',
                                        style: GridButtonStyle.danger,
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

            // Top-center "SHARING WITH N" pill (with paused-state from notifier).
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(child: _buildSharingPill()),
              ),
            ),

            // Right column FAB stack — compass, globe reset, center-on-me.
            Positioned(
              right: 16,
              top: 100,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCompassButton(isDarkMode, colorScheme),
                  const SizedBox(height: 10),
                  // Globe reset
                  FloatingActionButton(
                    heroTag: 'reset_view_fab',
                    backgroundColor: _isAtResetView
                        ? colorScheme.primary
                        : (isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.85)),
                    onPressed: _resetToInitialZoom,
                    tooltip: 'Reset view',
                    elevation: _isAtResetView ? 6 : 2,
                    mini: true,
                    child: Icon(
                      Icons.public_rounded,
                      color: _isAtResetView
                          ? Colors.white
                          : (isDarkMode ? colorScheme.primary : Colors.black),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Center on user
                  FloatingActionButton(
                    heroTag: 'center_on_user_fab',
                    backgroundColor: _followUser
                        ? colorScheme.primary
                        : (isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.85)),
                    onPressed: () {
                      final target = _locationManager?.currentLatLng ?? _mapController.camera.center;
                      if (target != null) {
                        _mapController.move(target, 16.0);
                      }
                      setState(() {
                        _followUser = true;
                        _isAtResetView = false;
                      });
                    },
                    tooltip: 'Center on me',
                    elevation: _followUser ? 6 : 2,
                    mini: true,
                    child: Icon(
                      Icons.my_location_rounded,
                      color: _followUser
                          ? Colors.white
                          : (isDarkMode ? colorScheme.primary : Colors.black),
                    ),
                  ),
                ],
              ),
            ),

            // Map Selector Overlay — removed (theme follows system brightness now).


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
        // Orient north when tapped.
        final center = _mapController.camera.center;
        if (center != null) {
          _mapController.moveAndRotate(
            center,
            _mapController.camera.zoom,
            0,
          );
        }
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

