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

import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/blocs/map/map_state.dart';
import 'package:grid_frontend/widgets/user_map_marker.dart';
import 'package:grid_frontend/widgets/map_scroll_window.dart';
import 'package:grid_frontend/widgets/user_info_bubble.dart';
import 'package:grid_frontend/screens/settings/settings_page.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/widgets/onboarding_modal.dart';

import '../../services/backwards_compatibility_service.dart';


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
  bool _followUser = true;
  double _zoom = 18;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapController = MapController();
    _initializeServices();
    _loadMapProvider();
    
    // Show onboarding modal if user hasn't seen it yet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OnboardingModal.showOnboardingIfNeeded(context);
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

    final prefs = await SharedPreferences.getInstance();
    final isIncognitoMode = prefs.getBool('incognito_mode') ?? false;

    if (!isIncognitoMode) {
      _locationManager.startTracking();
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _mapMoveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _mapController.dispose();
    _syncManager.stopSync();
    _locationManager.stopTracking();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncManager.handleAppLifecycleState(state == AppLifecycleState.resumed);
  }

  void _backwardsCompatibilityUpdate() async {
    final backwardsService = BackwardsCompatibilityService(
      userRepository,
      sharingPreferencesRepository,
    );

    await backwardsService.runBackfillIfNeeded();
  }

  void _sendPing() {
    _locationManager.grabLocationAndPing();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Location pinged to all active contacts and groups.')),
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

    return BlocListener<MapBloc, MapState>(
      listenWhen: (previous, current) =>
      previous.moveCount != current.moveCount && current.center != null,
      listener: (context, state) {
        if (state.center != null && _isMapReady) {
          setState(() {
            _followUser = false;  // Turn off following when moving to new location
            _targetUserId = state.selectedUserId;
          });
          _mapController.move(state.center!, _zoom);
          
          // Set timer to trigger bounce animation after map move completes
          _mapMoveTimer?.cancel();
          _mapMoveTimer = Timer(const Duration(milliseconds: 500), () {
            if (_targetUserId != null && mounted) {
              // Trigger a state update to force bounce animation
              setState(() {});
            }
          });
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
                initialCenter: LatLng(51.5, -0.09),
                initialZoom: _zoom,
                initialRotation: 0.0,
                minZoom: 5,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                onMapReady: () => setState(() => _isMapReady = true),
              ),
              children: [
                VectorTileLayer(
                  theme: _mapTheme,
                  tileProviders: TileProviders({'protomaps': _tileProvider!}),
                  fileCacheTtl: const Duration(days: 14),
                  memoryTileDataCacheMaxSize: 80,
                  memoryTileCacheMaxSize: 100,
                  concurrency: 5,
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
                      _mapController.move(_locationManager.currentLatLng ?? _mapController.camera.center, _zoom);
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
                  )
                ],
              ),
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