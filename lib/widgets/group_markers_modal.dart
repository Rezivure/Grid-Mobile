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
import 'grid/grid_mono.dart';

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
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          color: GridTokens.bg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(GridTokens.r2Xl),
          ),
          border: Border(
            top: BorderSide(color: GridTokens.hairline),
            left: BorderSide(color: GridTokens.hairline),
            right: BorderSide(color: GridTokens.hairline),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHandle(),
              _buildHeader(),
              Flexible(
                child: _isLoading
                    ? _buildLoadingState()
                    : _markers.isEmpty
                        ? _buildEmptyState()
                        : _buildList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: GridTokens.hairlineStrong,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    final count = _markers.length;
    final subtitle = _isLoading
        ? 'Loading markers in ${widget.roomName}'
        : '$count marker${count != 1 ? 's' : ''} in ${widget.roomName}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: GridTokens.mintFaint,
              borderRadius: BorderRadius.circular(GridTokens.rSm),
              border: Border.all(color: GridTokens.mintSoft),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.location_on_rounded,
              size: 18,
              color: GridTokens.mint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Group markers',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.015,
                    color: GridTokens.text,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 12.5,
                    color: GridTokens.text2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: GridTokens.text2,
              size: 22,
            ),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(GridTokens.mint),
            ),
          ),
          const SizedBox(height: 14),
          const GridMono(
            'LOADING MARKERS',
            size: 11,
            color: GridTokens.text3,
            letterSpacing: 0.12,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: GridTokens.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: GridTokens.hairline),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.location_off_rounded,
              size: 32,
              color: GridTokens.text3,
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
              color: GridTokens.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Markers added to the map will appear here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              color: GridTokens.text2,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: GridMono(
            'MARKERS',
            size: 10,
            color: GridTokens.text3,
            letterSpacing: 0.12,
          ),
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            itemCount: _markers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final marker = _markers[index];
              final distance =
                  _formatDistance(marker.latitude, marker.longitude);
              return _MarkerTile(
                marker: marker,
                iconData: _resolveIconData(marker),
                distance: distance,
                onTap: () => _navigateToMarker(marker),
              );
            },
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: GridTokens.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.hairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: GridTokens.mintFaint,
                  borderRadius: BorderRadius.circular(GridTokens.rSm),
                  border: Border.all(color: GridTokens.mintSoft),
                ),
                alignment: Alignment.center,
                child: Icon(
                  iconData,
                  size: 20,
                  color: GridTokens.mint,
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
                        color: GridTokens.text,
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
                          color: GridTokens.text2,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (distance.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.navigation_outlined,
                            size: 12,
                            color: GridTokens.mint,
                          ),
                          const SizedBox(width: 4),
                          GridMono(
                            distance,
                            uppercase: false,
                            size: 11,
                            letterSpacing: 0.04,
                            color: GridTokens.mint,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: GridTokens.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
