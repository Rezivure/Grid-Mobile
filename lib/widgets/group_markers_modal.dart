import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grid_frontend/models/map_icon.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:provider/provider.dart';

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
      final markers = await widget.mapIconRepository.getIconsForRoom(widget.roomId);
      
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
  
  Widget _buildMarkerIcon(MapIcon marker) {
    if (marker.iconType == 'icon') {
      // Map icon names to Flutter icons
      IconData iconData;
      switch (marker.iconData.toLowerCase()) {
        case 'pin':
          iconData = Icons.push_pin;
          break;
        case 'warning':
          iconData = Icons.warning;
          break;
        case 'food':
          iconData = Icons.restaurant;
          break;
        case 'car':
          iconData = Icons.directions_car;
          break;
        case 'home':
          iconData = Icons.home;
          break;
        case 'star':
          iconData = Icons.star;
          break;
        case 'heart':
          iconData = Icons.favorite;
          break;
        case 'flag':
          iconData = Icons.flag;
          break;
        default:
          iconData = Icons.place;
      }
      
      return Icon(
        iconData,
        size: 24,
        color: Theme.of(context).colorScheme.primary,
      );
    } else {
      // For SVG types or unknown, show a default icon
      return Icon(
        Icons.place,
        size: 24,
        color: Theme.of(context).colorScheme.primary,
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outline.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Group Markers',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_markers.length} marker${_markers.length != 1 ? 's' : ''} in ${widget.roomName}',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                    ),
                  )
                : _markers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_off,
                              size: 64,
                              color: colorScheme.onSurface.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No markers yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Markers added to the map will appear here',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurface.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _markers.length,
                        itemBuilder: (context, index) {
                          final marker = _markers[index];
                          final distance = _formatDistance(marker.latitude, marker.longitude);
                          
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceVariant.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.outline.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _navigateToMarker(marker),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      // Icon
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Center(
                                          child: _buildMarkerIcon(marker),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      
                                      // Info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              marker.name ?? 
                                                (marker.iconData.substring(0, 1).toUpperCase() + 
                                                 marker.iconData.substring(1)),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.onSurface,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (marker.description != null && marker.description!.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                marker.description!,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: colorScheme.onSurface.withOpacity(0.6),
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                            if (distance.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.navigation_outlined,
                                                    size: 14,
                                                    color: colorScheme.primary,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    distance,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: colorScheme.primary,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      
                                      // Navigation arrow
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16,
                                        color: colorScheme.onSurface.withOpacity(0.3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}