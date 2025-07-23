import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
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
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/widgets/user_map_marker.dart';
import 'package:grid_frontend/widgets/map_scroll_window.dart';
import 'package:grid_frontend/widgets/user_info_bubble.dart';
import 'package:grid_frontend/screens/settings/settings_page.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/widgets/onboarding_modal.dart';
import 'package:grid_frontend/services/subscription_service.dart';
import 'package:grid_frontend/screens/settings/subscription_screen.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;

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
  late final MapController _mapController;
  late final LocationManager _locationManager;
  late final RoomService _roomService;
  late final UserService _userService;
  late final SyncManager _syncManager;
  late final UserRepository userRepository;
  late final SharingPreferencesRepository sharingPreferencesRepository;

  bool _isMapReady = false;
  bool _followUser = false;  // Changed default to false to prevent initial movement
  double _zoom = 10;  // Changed default from 12 to 10
  bool _initialZoomCalculated = false;
  LatLng? _initialCenter;  // Store the calculated center point

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
  
  // Map style selector
  bool _showMapSelector = false;
  String _currentMapStyle = 'base'; // 'base' or 'satellite'
  final SubscriptionService _subscriptionService = SubscriptionService();
  String? _satelliteMapToken;
  
  // SharedPreferences keys
  static const String _mapStyleKey = 'selected_map_style';

  @override
  void initState() {
    super.initState();
    print('[SMART ZOOM] initState - initial zoom: $_zoom');
    WidgetsBinding.instance.addObserver(this);
    _mapController = MapController();
    _initializeServices();
    _loadMapProvider();
    _loadMapStylePreference();
    
    // Show onboarding modal if user hasn't seen it yet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OnboardingModal.showOnboardingIfNeeded(context);
      print('[SMART ZOOM] Post frame callback - locationManager.currentLatLng: ${_locationManager.currentLatLng}');
    });
  }

  Future<void> _initializeServices() async {
    _roomService = context.read<RoomService>();
    _userService = context.read<UserService>();
    _locationManager = context.read<LocationManager>();
    _syncManager = context.read<SyncManager>();
    userRepository = context.read<UserRepository>();
    sharingPreferencesRepository = context.read<SharingPreferencesRepository>();

    _syncManager.initialize();
    
    // Clean up orphaned location data on startup
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        await _syncManager.cleanupOrphanedLocationData();
      } catch (e) {
        print('[MapTab] Error cleaning up orphaned locations: $e');
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final isIncognitoMode = prefs.getBool('incognito_mode') ?? false;

    if (!isIncognitoMode) {
      _locationManager.startTracking();
    }
    
    // Listen for location updates to trigger zoom calculation
    _locationManager.addListener(_onLocationUpdate);
  }
  
  void _onLocationUpdate() {
    print('[SMART ZOOM] Location update received, currentLatLng: ${_locationManager.currentLatLng}');
    // Check if we can calculate zoom now
    if (!_initialZoomCalculated && _isMapReady && _locationManager.currentLatLng != null) {
      print('[SMART ZOOM] Location available, checking for user locations...');
      final mapBloc = context.read<MapBloc>();
      final userLocations = mapBloc.state.userLocations;
      // Always calculate zoom, even with no contacts
      print('[SMART ZOOM] All conditions met, calculating zoom...');
      final result = _calculateOptimalZoomAndCenter(
        _locationManager.currentLatLng!, 
        userLocations
      );
      _zoom = result.zoom;
      _mapController.moveAndRotate(result.center, _zoom, 0);
      setState(() {
        _initialZoomCalculated = true;
      });
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _mapMoveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _locationManager.removeListener(_onLocationUpdate);
    _mapController.dispose();
    _syncManager.stopSync();
    _locationManager.stopTracking();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncManager.handleAppLifecycleState(state == AppLifecycleState.resumed);
    
    // Refresh satellite token when app resumes if using satellite maps
    if (state == AppLifecycleState.resumed && _currentMapStyle == 'satellite') {
      _refreshSatelliteTokenIfNeeded();
    }
  }

  void _backwardsCompatibilityUpdate() async {
    final backwardsService = BackwardsCompatibilityService(
      userRepository,
      sharingPreferencesRepository,
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
        print('Refreshed satellite map token');
      }
    } catch (e) {
      print('Error refreshing satellite token: $e');
    }
  }

  void _sendPing() {
    _locationManager.grabLocationAndPing();
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
        print('Dotenv not loaded, attempting to reload...');
        try {
          await dotenv.load(fileName: ".env");
        } catch (e) {
          print('Failed to reload dotenv: $e');
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final mapUrl = prefs.getString('maps_url') ?? 'https://map.mygrid.app/v1/protomaps.pmtiles';

      _mapTheme = ProtomapsThemes.light();
      _tileProvider = await PmTilesVectorTileProvider.fromSource(mapUrl);

      context.read<MapBloc>().add(MapInitialize());
      setState(() {});
    } catch (e) {
      print('Error loading map provider: $e');
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
            setState(() {
              _currentMapStyle = 'satellite';
              _satelliteMapToken = token;
            });
            print('Loaded satellite map style with token');
          } else {
            // Failed to get token, revert to base maps
            setState(() {
              _currentMapStyle = 'base';
            });
            await prefs.setString(_mapStyleKey, 'base');
            print('Failed to get satellite token, reverting to base maps');
          }
        } else {
          // No subscription, revert to base maps
          setState(() {
            _currentMapStyle = 'base';
          });
          await prefs.setString(_mapStyleKey, 'base');
          print('No active subscription, reverting to base maps');
        }
      } else {
        setState(() {
          _currentMapStyle = savedStyle;
        });
      }
    } catch (e) {
      print('Error loading map style preference: $e');
      // Default to base maps on error
      setState(() {
        _currentMapStyle = 'base';
      });
    }
  }

  void _showMapErrorDialog() {
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


  // Returns both optimal zoom and center point
  MapZoomResult _calculateOptimalZoomAndCenter(LatLng userPosition, List<UserLocation> userLocations) {
    print('[SMART ZOOM] Calculating optimal zoom and center...');
    print('[SMART ZOOM] User position: ${userPosition.latitude}, ${userPosition.longitude}');
    print('[SMART ZOOM] Number of user locations: ${userLocations.length}');
    
    if (userLocations.isEmpty) {
      print('[SMART ZOOM] No contacts found, returning default zoom 10');
      return MapZoomResult(zoom: 10.0, center: userPosition);
    }

    // Find the closest contact
    double minDistance = double.infinity;
    UserLocation? closestLocation;
    for (final location in userLocations) {
      final distance = const Distance().as(LengthUnit.Meter, userPosition, location.position);
      if (distance < minDistance) {
        minDistance = distance;
        closestLocation = location;
      }
    }
    
    if (closestLocation == null) {
      return MapZoomResult(zoom: 10.0, center: userPosition);
    }
    
    print('[SMART ZOOM] Closest contact: ${closestLocation.userId} at ${minDistance.toStringAsFixed(0)} meters');
    
    // Calculate the center point between user and closest contact
    final centerLat = (userPosition.latitude + closestLocation.position.latitude) / 2;
    final centerLng = (userPosition.longitude + closestLocation.position.longitude) / 2;
    final centerPoint = LatLng(centerLat, centerLng);
    
    print('[SMART ZOOM] Center point: ${centerLat}, ${centerLng}');

    // Calculate zoom based on distance
    // Balance between showing both points and not zooming out too far
    double zoomLevel;
    if (minDistance < 100) {
      zoomLevel = 16.0; // Very close (slightly reduced for safety)
    } else if (minDistance < 500) {
      zoomLevel = 14.5; // Walking distance
    } else if (minDistance < 1000) {
      zoomLevel = 13.5; // Close neighborhood
    } else if (minDistance < 5000) {
      zoomLevel = 11.5; // Same area
    } else if (minDistance < 20000) {
      zoomLevel = 9.5; // Same city
    } else if (minDistance < 50000) {
      zoomLevel = 8.5; // Metro area
    } else if (minDistance < 100000) {
      zoomLevel = 7.5; // Multiple cities
    } else if (minDistance < 250000) {
      zoomLevel = 6.5; // State view
    } else if (minDistance < 500000) {
      zoomLevel = 5.5; // Multi-state view
    } else if (minDistance < 1000000) {
      zoomLevel = 4.5; // Large region
    } else if (minDistance < 2500000) {
      zoomLevel = 3.5; // Cross-country (e.g. East to West coast)
    } else if (minDistance < 5000000) {
      zoomLevel = 2.5; // Continental view
    } else {
      zoomLevel = 2.0; // Maximum zoom out for intercontinental
    }
    
    print('[SMART ZOOM] Calculated zoom level: $zoomLevel');
    return MapZoomResult(zoom: zoomLevel, center: centerPoint);
  }

  void _onMarkerTap(String userId, LatLng position) async {
    // Update map state with selected user
    context.read<MapBloc>().add(MapMoveToUser(userId));
    
    // Fetch user display name
    String displayName = userId.split(':')[0].replaceFirst('@', ''); // Default fallback
    try {
      final user = await userRepository.getUserById(userId);
      if (user != null && user.displayName != null && user.displayName!.isNotEmpty) {
        displayName = user.displayName!;
      }
    } catch (e) {
      print('Error fetching user display name: $e');
    }
    
    setState(() {
      _selectedUserId = userId;
      _bubblePosition = position;
      _selectedUserName = displayName;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_tileProvider == null) {
      return _buildMapLoadingState(context);
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    // Don't pre-calculate - let onMapReady handle it

    return BlocListener<MapBloc, MapState>(
      listenWhen: (previous, current) =>
      (previous.moveCount != current.moveCount && current.center != null) ||
      (previous.userLocations.length != current.userLocations.length),
      listener: (context, state) {
        // Handle map movement
        if (state.center != null && _isMapReady) {
          setState(() {
            _followUser = false;  // Turn off following when moving to new location
            _targetUserId = state.selectedUserId;
          });
          
          // Go straight to street level zoom when clicking on a user
          const double targetZoom = 14.0;
          
          print('[SMART ZOOM] User clicked - jumping to street level zoom: $targetZoom');
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
        
        // Handle initial zoom calculation when user locations arrive or change
        if (!_initialZoomCalculated && _isMapReady && _locationManager.currentLatLng != null) {
          print('[SMART ZOOM] BlocListener triggered - conditions met for zoom calculation');
          final result = _calculateOptimalZoomAndCenter(
            _locationManager.currentLatLng!, 
            state.userLocations
          );
          _zoom = result.zoom;
          print('[SMART ZOOM] Moving map to center point with zoom: $_zoom');
          _mapController.moveAndRotate(result.center, _zoom, 0);
          setState(() {
            _initialZoomCalculated = true;
          });
        } else if (!_initialZoomCalculated) {
          print('[SMART ZOOM] BlocListener - conditions not met:');
          print('  - _initialZoomCalculated: $_initialZoomCalculated');
          print('  - _isMapReady: $_isMapReady');
          print('  - currentLatLng: ${_locationManager.currentLatLng}');
          print('  - userLocations.length: ${state.userLocations.length}');
        }
      },
      child: Scaffold(
            body: Stack(
              children: [
                SizedBox(
                    height: MediaQuery.of(context).size.height * 3/4,
                child:
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    onTap: (tapPosition, latLng) {
                      // Clear selection when tapping on map
                      context.read<MapBloc>().add(MapClearSelection());
                      // Also clear bubble if shown
                      setState(() {
                        _bubblePosition = null;
                        _selectedUserId = null;
                        _selectedUserName = null;
                      });
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
                    },
                    initialCenter: _locationManager.currentLatLng ?? LatLng(51.5, -0.09),
                    initialZoom: _zoom,
                    initialRotation: 0.0,
                    minZoom: 1,
                    maxZoom: 18,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                    onMapReady: () {
                      print('[SMART ZOOM] Map is ready!');
                      setState(() => _isMapReady = true);
                      
                      // Calculate optimal zoom when map is ready
                      if (!_initialZoomCalculated) {
                        // Try to get current position if we don't have it yet
                        if (_locationManager.currentLatLng == null) {
                          print('[SMART ZOOM] No location yet, requesting current position...');
                          _locationManager.grabLocationAndPing().then((_) {
                            print('[SMART ZOOM] Got location: ${_locationManager.currentLatLng}');
                            if (_locationManager.currentLatLng != null && mounted) {
                              final mapBloc = context.read<MapBloc>();
                              final userLocations = mapBloc.state.userLocations;
                              // Always calculate zoom, even with no contacts
                              final result = _calculateOptimalZoomAndCenter(
                                _locationManager.currentLatLng!, 
                                userLocations
                              );
                              _zoom = result.zoom;
                              print('[SMART ZOOM] Moving to center point with zoom: $_zoom');
                              _mapController.moveAndRotate(result.center, _zoom, 0);
                              setState(() {
                                _initialZoomCalculated = true;
                              });
                            }
                          });
                        } else {
                          // We already have location
                          final mapBloc = context.read<MapBloc>();
                          final userLocations = mapBloc.state.userLocations;
                          // Always calculate zoom, even with no contacts
                          final result = _calculateOptimalZoomAndCenter(
                            _locationManager.currentLatLng!, 
                            userLocations
                          );
                          _zoom = result.zoom;
                          print('[SMART ZOOM] Moving map to center with zoom: $_zoom');
                          _mapController.moveAndRotate(result.center, _zoom, 0);
                          setState(() {
                            _initialZoomCalculated = true;
                          });
                        }
                      }
                    },
                  ),
              children: [
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
              ],
            ),
            ),

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
                  FloatingActionButton(
                    heroTag: "centerUserBtn",
                    backgroundColor: _followUser
                        ? colorScheme.primary
                        : (isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8)),
                    onPressed: () {
                      // can add any pre center logic here
                      _mapController.move(_locationManager.currentLatLng ?? _mapController.camera.center, _mapController.camera.zoom);
                      setState(() {
                        _followUser = true;
                      });
                    },
                    child: Icon(
                        Icons.my_location,
                        color: _followUser
                            ? Colors.white
                            : (isDarkMode ? colorScheme.primary : Colors.black)
                    ),
                    mini: true,
                  ),
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
                  if (!utils.isCustomHomeserver(_roomService.getMyHomeserver()))
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
                ],
              ),
            ),

            // Map Selector Overlay (only for default homeserver)
            if (_showMapSelector && !utils.isCustomHomeserver(_roomService.getMyHomeserver()))
              Positioned(
                top: 300,
                right: 16,
                child: _buildMapSelector(isDarkMode, colorScheme),
              ),
              
            Align(
              alignment: Alignment.bottomCenter,
              child: MapScrollWindow(),
            ),
          ],
        ),
      ),
    );
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
              angle: -_currentMapRotation * (3.141592653589793 / 180), // Convert degrees to radians
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
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDarkMode ? colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Base Map Option
          _buildMapOption(
            title: 'Standard Map',
            imagePath: 'assets/extras/basemaps.png',
            isSelected: _currentMapStyle == 'base',
            onTap: () {
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
            onTap: () async {
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
      ),
    );
  }
  
  Widget _buildMapOption({
    required String title,
    required String imagePath,
    required bool isSelected,
    required VoidCallback onTap,
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
    if (style == 'satellite') {
      // Check subscription and get token
      final hasSubscription = await _subscriptionService.hasActiveSubscription();
      if (!hasSubscription) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SubscriptionScreen()),
        );
        return;
      }
      
      // Try to get a map token (will use cached if valid)
      final token = await _subscriptionService.getMapToken();
      if (token == null) {
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

