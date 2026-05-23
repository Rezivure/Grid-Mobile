import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grid_frontend/models/map_icon.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';

import '../styles/tokens.dart';
import '../styles/grid_colors.dart';
import 'grid/grid_mono.dart';
import 'grid/grid_segmented.dart';
import 'grid/grid_sheet.dart';

class GroupMarkersModal extends StatefulWidget {
  final String roomId;
  final String roomName;
  final MapIconRepository mapIconRepository;

  const GroupMarkersModal({
    Key? key,
    required this.roomId,
    required this.roomName,
    required this.mapIconRepository,
  }) : super(key: key);

  @override
  _GroupMarkersModalState createState() => _GroupMarkersModalState();
}

class _GroupMarkersModalState extends State<GroupMarkersModal> {
  List<MapIcon> _markers = [];
  bool _isLoading = true;
  LatLng? _currentLocation;
  final Distance _distance = Distance();

  @override
  void initState() {
    super.initState();
    _loadMarkers();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      print('Error getting current location: $e');
    }
  }

  Future<void> _loadMarkers() async {
    try {
      final markers =
          await widget.mapIconRepository.getIconsForRoom(widget.roomId);

      if (mounted) {
        setState(() {
          _markers = markers;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading markers: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDistance(double latitude, double longitude) {
    if (_currentLocation == null) return '';

    final markerLocation = LatLng(latitude, longitude);
    final distanceInMeters = _distance.as(
      LengthUnit.Meter,
      _currentLocation!,
      markerLocation,
    );

    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)} m away';
    } else {
      final distanceInKm = distanceInMeters / 1000;
      return '${distanceInKm.toStringAsFixed(1)} km away';
    }
  }

  void _navigateToMarker(MapIcon marker) {
    // Navigate to the marker on the map
    context.read<MapBloc>().add(MapCenterOnLocation(
          LatLng(marker.latitude, marker.longitude),
          zoom: 16.0,
        ));

    // Close the modal - keep the current group selection
    Navigator.of(context).pop();

    // Don't change the subscreen selection - stay in the current group view
    // This keeps the map icons loaded for the current group
  }

  IconData _resolveIconData(MapIcon marker) {
    if (marker.iconType == 'icon') {
      switch (marker.iconData.toLowerCase()) {
        case 'pin':
          return Icons.push_pin;
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
    return Icons.place;
  }

  @override
  Widget build(BuildContext context) {
    final count = _markers.length;
    final subtitle = _isLoading
        ? 'Loading markers in ${widget.roomName}'
        : '$count marker${count != 1 ? 's' : ''} in ${widget.roomName}';
    return GridSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridSheetHeader(
            title: 'Group markers',
            subtitle: subtitle,
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: _isLoading
                ? _buildLoadingState()
                : _markers.isEmpty
                    ? _buildEmptyState()
                    : _buildList(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(context.gridColors.mint),
            ),
          ),
          const SizedBox(height: 14),
          GridMono(
            'LOADING MARKERS',
            size: 11,
            color: context.gridColors.text3,
            letterSpacing: 0.12,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: context.gridColors.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: context.gridColors.hairline),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.location_off_rounded,
              size: 32,
              color: context.gridColors.text3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No markers yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.01,
              color: context.gridColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Markers added to the map will appear here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              color: context.gridColors.text2,
              height: 1.35,
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GridSectionHeader(text: 'MARKERS'),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Container(
              decoration: BoxDecoration(
                color: context.gridColors.surface,
                borderRadius: BorderRadius.circular(GridTokens.rMd),
                border: Border.all(color: context.gridColors.hairline),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _markers.length; i++) ...[
                    _MarkerTile(
                      marker: _markers[i],
                      iconData: _resolveIconData(_markers[i]),
                      distance: _formatDistance(
                        _markers[i].latitude,
                        _markers[i].longitude,
                      ),
                      onTap: () => _navigateToMarker(_markers[i]),
                    ),
                    if (i < _markers.length - 1)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: context.gridColors.hairline,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkerTile extends StatelessWidget {
  const _MarkerTile({
    required this.marker,
    required this.iconData,
    required this.distance,
    required this.onTap,
  });

  final MapIcon marker;
  final IconData iconData;
  final String distance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = marker.name ??
        (marker.iconData.isNotEmpty
            ? marker.iconData.substring(0, 1).toUpperCase() +
                marker.iconData.substring(1)
            : 'Marker');
    final hasDescription =
        marker.description != null && marker.description!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.gridColors.mintFaint,
                  borderRadius: BorderRadius.circular(GridTokens.rSm),
                  border: Border.all(color: context.gridColors.mintSoft),
                ),
                alignment: Alignment.center,
                child: Icon(
                  iconData,
                  size: 20,
                  color: context.gridColors.mint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: context.gridColors.text,
                      ),
                    ),
                    if (hasDescription) ...[
                      const SizedBox(height: 3),
                      Text(
                        marker.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 12.5,
                          color: context.gridColors.text2,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (distance.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.navigation_outlined,
                            size: 12,
                            color: context.gridColors.mint,
                          ),
                          const SizedBox(width: 4),
                          GridMono(
                            distance,
                            uppercase: false,
                            size: 11,
                            letterSpacing: 0.04,
                            color: context.gridColors.mint,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.gridColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
