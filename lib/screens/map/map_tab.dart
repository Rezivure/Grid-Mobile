import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vector_renderer;
import 'package:provider/provider.dart'; // <--- Make sure Provider is imported

import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/blocs/map/map_state.dart';
import 'package:grid_frontend/widgets/user_map_marker.dart';
import 'package:grid_frontend/widgets/map_scroll_window.dart';
import 'package:grid_frontend/widgets/user_info_bubble.dart';
import 'package:grid_frontend/screens/settings/settings_page.dart';

import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/repositories/location_repository.dart';

class MapTab extends StatefulWidget {
  final LatLng? friendLocation;

  const MapTab({this.friendLocation, Key? key}) : super(key: key);

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with TickerProviderStateMixin {
  late final MapController _mapController;
  late final RoomService _roomService;     // Accessed via Provider
  late final UserService _userService;     // Accessed via Provider

  bool _isMapReady = false;
  double zoom = 18;

  VectorTileProvider? tileProvider;
  late vector_renderer.Theme mapTheme;

  // Bubble variables
  LatLng? _bubblePosition;
  String? _selectedUserId;
  String? _selectedUserName;

  AnimationController? _animationController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    // Fetch services from Provider
    _roomService = context.read<RoomService>();
    _userService = context.read<UserService>();

    _loadMapProvider();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadMapProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mapUrl = prefs.getString('maps_url') ?? 'https://map.mygrid.app/v1/protomaps.pmtiles';

      mapTheme = ProtomapsThemes.light();
      tileProvider = await PmTilesVectorTileProvider.fromSource(mapUrl);

      // Trigger map initialization event
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Error'),
          content: const Text('Invalid map URL. You will be logged out and redirected to login.'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Handle logout and navigate to login screen
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!_isMapReady) {
      print('Map is not ready yet.');
      return;
    }

    final currentCenter = _mapController.camera.center;
    final currentZoom = _mapController.camera.zoom;

    final latTween = Tween<double>(
      begin: currentCenter.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: currentCenter.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: currentZoom,
      end: destZoom,
    );

    _animationController?.dispose();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    Animation<double> animation = CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeInOut,
    );

    _animationController!.addListener(() {
      final nextLat = latTween.evaluate(animation);
      final nextLng = lngTween.evaluate(animation);
      final nextZoom = zoomTween.evaluate(animation);

      _mapController.move(LatLng(nextLat, nextLng), nextZoom);
    });

    _animationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationController?.dispose();
        _animationController = null;
      }
    });

    _animationController!.forward();
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    if (tileProvider == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return BlocBuilder<MapBloc, MapState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.error != null) {
          return Center(child: Text('Error: ${state.error}'));
        }

        return Scaffold(
          body: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: state.center ?? LatLng(51.5, -0.09),
                  initialZoom: state.zoom,
                  initialRotation: 0.0,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                  onMapReady: () {
                    setState(() {
                      _isMapReady = true;
                      print('Map is ready');
                    });
                  },
                ),
                children: <Widget>[
                  VectorTileLayer(
                    theme: mapTheme,
                    tileProviders: TileProviders({
                      'protomaps': tileProvider!,
                    }),
                    fileCacheTtl: const Duration(hours: 24),
                    concurrency: 25,
                  ),
                  CurrentLocationLayer(
                    followOnLocationUpdate: FollowOnLocationUpdate.always,
                    style: const LocationMarkerStyle(),
                  ),
                  MarkerLayer(
                    markers: state.userLocations.map((userLocation) {
                      return Marker(
                        width: 60.0,
                        height: 70.0,
                        point: userLocation.position,
                        child: GestureDetector(
                          onTap: () => _onMarkerTap(userLocation.userId, userLocation.position),
                          child: UserMapMarker(userId: userLocation.userId),
                        ),
                      );
                    }).toList(),
                  ),
                ],
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
                  child: Icon(Icons.menu,
                      color: isDarkMode ? colorScheme.primary : Colors.black),
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
                      onPressed: () {
                        _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom,
                        );
                      },
                      child: Icon(Icons.explore,
                          color: isDarkMode ? colorScheme.primary : Colors.black),
                      mini: true,
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      heroTag: "centerUserBtn",
                      backgroundColor: isDarkMode ? colorScheme.surface : Colors.white.withOpacity(0.8),
                      onPressed: () {
                        context.read<MapBloc>().add(MapCenterOnUser());
                      },
                      child: Icon(Icons.my_location,
                          color: isDarkMode ? colorScheme.primary : Colors.black),
                      mini: true,
                    ),
                  ],
                ),
              ),

              Align(
                alignment: Alignment.bottomCenter,
                child: MapScrollWindow(), // MapScrollWindow also uses Provider internally if needed
              ),
            ],
          ),
        );
      },
    );
  }
}
