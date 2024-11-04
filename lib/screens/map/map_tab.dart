import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:grid_frontend/widgets/user_map_marker.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/selected_subscreen_provider.dart';
import '../../providers/user_location_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/map_scroll_window.dart';
import '../../screens/settings/settings_page.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:matrix/matrix.dart';
import '../../services/location_broadcast_service.dart';
import '../../services/location_tracking_service.dart';
import 'dart:async';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vector_renderer;
import '../../providers/selected_user_provider.dart';
import '../../services/database_service.dart';
import '../../widgets/user_info_bubble.dart';

class MapTab extends StatefulWidget {
  final LatLng? friendLocation;
  MapTab({this.friendLocation});

  @override
  _MapTabState createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with TickerProviderStateMixin {
  LatLng? _currentPosition;
  late final MapController _mapController;
  bool _isMapReady = false;
  bool _isLoading = true;
  bool _isCenteredOnUser = false;
  double zoom = 18;
  Object? _error;
  VectorTileProvider? tileProvider;
  late vector_renderer.Theme mapTheme;

  SelectedUserProvider? _selectedUserProvider;
  AnimationController? _animationController;

  // Variables for user bubble
  LatLng? _bubblePosition;
  String? _selectedUserId;
  String? _selectedUserName;

  // Flag to ensure locations are fetched only once
  bool _locationsFetched = false;
  StreamSubscription<SyncUpdate>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _startLocationServices();
    setMapProvider();
    _waitForClientSync();
    _fetchInitialLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final selectedUserProvider = Provider.of<SelectedUserProvider>(context);

    if (_selectedUserProvider != selectedUserProvider) {
      _selectedUserProvider?.removeListener(_onSelectedUserChanged);
      _selectedUserProvider = selectedUserProvider;
      _selectedUserProvider!.addListener(_onSelectedUserChanged);
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _mapController.dispose();
    _selectedUserProvider?.removeListener(_onSelectedUserChanged);
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> setMapProvider() async {
    try {
      // Fetch the map URL from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final mapUrl = prefs.getString('maps_url') ?? 'https://map.mygrid.app/v1/protomaps.pmtiles';

      mapTheme = _loadMapTheme();

      // Attempt to load the map tiles
      tileProvider = await PmTilesVectorTileProvider.fromSource(mapUrl);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading map theme or tile provider: $e');

      // If an error occurs, log the user out and navigate to login
      _handleInvalidMapUrlError();
    }
  }

  Future<void> _handleInvalidMapUrlError() async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text('Invalid map URL. You will be logged out and redirected to login.'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close the dialog
                // Proceed to log the user out and navigate to login
                await _logoutAndNavigate();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logoutAndNavigate() async {
    try {
      final client = Provider.of<Client>(context, listen: false);
      if (client.isLogged()) {
        await client.logout();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      print('Error during logout or navigation: $e');
    }
  }

  // Return the correct Theme type
  vector_renderer.Theme _loadMapTheme() {
    return ProtomapsThemes.light();
  }

  Future<void> _initializeMap() async {
    if (widget.friendLocation != null) {
      _animatedMapMove(widget.friendLocation!, zoom);
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchInitialLocation() async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    await locationProvider.determinePosition();
    if (locationProvider.currentPosition != null && _isMapReady) {
      _centerOnUser();
    } else {
      print('Unable to get initial location.');
    }
  }

  Future<void> _startLocationServices() async {
    // Start LocationBroadcastService and LocationTrackingService
    final locationBroadcastService = Provider.of<LocationBroadcastService>(context, listen: false);
    final locationTrackingService = Provider.of<LocationTrackingService>(context, listen: false);

    // Start broadcasting and tracking services
    locationBroadcastService.startBroadcastingLocation();
    locationTrackingService.startService();
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!_isMapReady) {
      print('Map is not ready yet.');
      return;
    }

    final latTween = Tween<double>(
      begin: _mapController.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: _mapController.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: _mapController.zoom,
      end: destZoom,
    );

    // Dispose of any previous controller
    _animationController?.dispose();

    // Create a new controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    Animation<double> animation = CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeInOut,
    );

    _animationController!.addListener(() {
      _mapController.move(
        LatLng(
          latTween.evaluate(animation),
          lngTween.evaluate(animation),
        ),
        zoomTween.evaluate(animation),
      );
    });

    _animationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationController?.dispose();
        _animationController = null;
      }
    });

    _animationController!.forward();
  }

  void _centerOnUser() {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);

    final currentPosition = locationProvider.currentPosition;
    if (currentPosition != null) {
      LatLng userLocation = LatLng(
        currentPosition.latitude!,
        currentPosition.longitude!,
      );
      _animatedMapMove(userLocation, _mapController.zoom);
    } else {
      print('Current position is null, cannot center on user.');
    }
  }




  void _orientNorth() {
    if (!_isMapReady) return;
    _mapController.rotate(0.0);
  }

  void _onSelectedUserChanged() async {
    try {
      final userId = _selectedUserProvider?.selectedUserId;
      print('Selected user ID in MapTab: $userId');
      if (userId != null) {
        await _moveToUserLocation(userId);
        // Reset the selectedUserId to prevent repeated moves
        _selectedUserProvider?.setSelectedUserId(null);
      }
    } catch (e, stackTrace) {
      print('Error in _onSelectedUserChanged: $e');
      print('Stack trace: $stackTrace');
    }
  }

  // Adjusted method to wait for client sync
  void _waitForClientSync() {
    final client = Provider.of<Client>(context, listen: false);

    // If already synced and rooms are available, proceed
    if (client.isLogged() && client.rooms.isNotEmpty) {
      _fetchUserLocations();
      _locationsFetched = true;
    } else {
      // Add listener for sync updates
      _syncSubscription = client.onSync.stream.listen((syncUpdate) {
        if (!_locationsFetched && client.rooms.isNotEmpty) {
          _fetchUserLocations();
          _locationsFetched = true;

          // Cancel the subscription as we no longer need it
          _syncSubscription?.cancel();
        }
      });
    }
  }

  void _fetchUserLocations() async {
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    await roomProvider.fetchAndUpdateLocations();
  }

  Future<void> _moveToUserLocation(String userId) async {
    try {
      final databaseService = Provider.of<DatabaseService>(context, listen: false);
      final userLocationData = await databaseService.getUserLocationById(userId);

      if (userLocationData != null) {
        final latitude = userLocationData.latitude;
        final longitude = userLocationData.longitude;

        final position = LatLng(latitude, longitude);

        _animatedMapMove(position, zoom);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location not available for this user.')),
        );
      }
    } catch (e, stackTrace) {
      print('Error in _moveToUserLocation: $e');
      print('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error moving to user location.')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    if (_isLoading || tileProvider == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Stack(
        children: [
          Consumer4<LocationProvider, SelectedSubscreenProvider,
              UserLocationProvider, RoomProvider>(
            builder: (context, locationProvider, selectedSubscreenProvider,
                userLocationProvider, roomProvider, child) {
              final selectedSubscreen = selectedSubscreenProvider.selectedSubscreen;
              final userLocations = userLocationProvider.getUserLocations(selectedSubscreen);

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  interactiveFlags: InteractiveFlag.all,
                  center: locationProvider.currentPosition != null
                      ? LatLng(
                    locationProvider.currentPosition!.latitude!,
                    locationProvider.currentPosition!.longitude!,
                  )
                      : LatLng(51.5, -0.09), // Default to London if no location
                  zoom: zoom,
                  maxZoom: 18,
                  minZoom: 3,
                  rotation: 0.0,
                  onMapReady: () {
                    setState(() {
                      _isMapReady = true;
                      print('Map is ready');
                      if (!_isCenteredOnUser && locationProvider.currentPosition != null) {
                        _centerOnUser();
                        _isCenteredOnUser = true;
                      }
                    });
                  },
                ),
                children: <Widget>[
                  VectorTileLayer(
                    theme: mapTheme,
                    tileProviders: TileProviders({
                      'protomaps': tileProvider!,
                    }),
                    fileCacheTtl: Duration(hours: 24),
                    concurrency: 25,
                  ),
                  CurrentLocationLayer(),
                  // Add the MarkerLayer with user avatars
                  MarkerLayer(
                    markers: userLocations.map<Marker>((userLocation) {
                      return Marker(
                        width: 60.0,
                        height: 70.0,
                        point: userLocation.position,
                        child: GestureDetector(
                          onTap: () {
                            // When a marker is tapped, display the bubble
                            setState(() {
                              _selectedUserId = userLocation.userId;
                              _bubblePosition = userLocation.position;
                              _selectedUserName = userLocation.userId
                                  .split(':')[0]
                                  .replaceFirst('@', '');
                            });
                          },
                          child: UserMapMarker(userId: userLocation.userId),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),

          // Show the bubble if a user is selected
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
                ).then((_) {
                  setState(() {});
                });
              },
              child: Icon(Icons.menu,
                  color: isDarkMode ? colorScheme.primary : Colors.black),
              mini: true,
            ),
          ),

          // Overlay buttons: Center User & Orient North
          Positioned(
            right: 16,
            top: 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: "orientNorthBtn",
                  backgroundColor: isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8),
                  onPressed: () {
                    _orientNorth();
                  },
                  child: Icon(Icons.explore,
                      color: isDarkMode ? colorScheme.primary : Colors.black),
                  mini: true,
                ),
                SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: "centerUserBtn",
                  backgroundColor: isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8),
                  onPressed: () {
                    _centerOnUser();
                  },
                  child: Icon(Icons.my_location,
                      color: isDarkMode ? colorScheme.primary : Colors.black),
                  mini: true,
                ),
              ],
            ),
          ),

          // Bottom Scrollable Window
          Align(
            alignment: Alignment.bottomCenter,
            child: MapScrollWindow(),
          ),
        ],
      ),
    );
  }
}
