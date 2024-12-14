import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

  bool _isMapReady = false;
  bool _followUser = true;
  double _zoom = 18;

  VectorTileProvider? _tileProvider;
  late vector_renderer.Theme _mapTheme;

  // Bubble variables
  LatLng? _bubblePosition;
  String? _selectedUserId;
  String? _selectedUserName;

  AnimationController? _animationController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapController = MapController();
    _initializeServices();
    _loadMapProvider();
  }

  void _initializeServices() {
    _roomService = context.read<RoomService>();
    _userService = context.read<UserService>();
    _locationManager = context.read<LocationManager>();
    _syncManager = context.read<SyncManager>();

    _syncManager.initialize();
    _locationManager.startTracking();
  }

  @override
  void dispose() {
    _animationController?.dispose();
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

  Future<void> _loadMapProvider() async {
    try {
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: const Text('Invalid map URL. You will be logged out and redirected to login.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }


  void _onMarkerTap(String userId, LatLng position) {
    setState(() {
      _selectedUserId = userId;
      _bubblePosition = position;
      _selectedUserName = userId.split(':')[0].replaceFirst('@', '');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_tileProvider == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    return BlocListener<MapBloc, MapState>(
      listenWhen: (previous, current) => previous.center != current.center,
      listener: (context, state) {
        if (state.center != null && _isMapReady) {
          setState(() {
            _followUser = false;  // Turn off following when moving to new location
          });
          _mapController.move(state.center!, _zoom);
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
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && _followUser) {
                    setState(() {
                      _followUser = false;
                    });
                  }
                },
                initialCenter: LatLng(51.5, -0.09),
                initialZoom: _zoom,
                initialRotation: 0.0,
                minZoom: 12,    // Add this line
                maxZoom: 18,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                onMapReady: () => setState(() => _isMapReady = true),
              ),
              children: [
                VectorTileLayer(
                  theme: _mapTheme,
                  tileProviders: TileProviders({'protomaps': _tileProvider!}),
                  fileCacheTtl: const Duration(hours: 24),
                  concurrency: 1,
                ),
                CurrentLocationLayer(
                  alignPositionOnUpdate: _followUser ? AlignOnUpdate.always : AlignOnUpdate.never,
                  style: const LocationMarkerStyle(),
                ),
                BlocBuilder<MapBloc, MapState>(
                  buildWhen: (previous, current) => previous.userLocations != current.userLocations,
                  builder: (context, state) {
                    return MarkerLayer(
                      markers: state.userLocations.map((userLocation) =>
                          Marker(
                            width: 60.0,
                            height: 70.0,
                            point: userLocation.position,
                            child: GestureDetector(
                              onTap: () => _onMarkerTap(userLocation.userId, userLocation.position),
                              child: UserMapMarker(userId: userLocation.userId),
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
                  FloatingActionButton(
                    heroTag: "orientNorthBtn",
                    backgroundColor: isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8),
                    onPressed: () => _mapController.moveAndRotate(
                      _mapController.camera.center,
                      _mapController.camera.zoom,
                      0,  // Set rotation to 0 (north)
                    ),
                    child: Icon(
                        Icons.explore,
                        color: isDarkMode ? colorScheme.primary : Colors.black
                    ),
                    mini: true,
                  ),
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
}