import 'dart:async';
import 'dart:math'; // For mathematical calculations
import 'package:grid_frontend/providers/location_provider.dart';
import 'package:grid_frontend/providers/room_provider.dart';
import 'package:matrix/matrix.dart';
import 'package:location/location.dart';

class LocationBroadcastService {
  final LocationProvider locationProvider;
  final RoomProvider roomProvider;

  LocationBroadcastService(this.locationProvider, this.roomProvider);

  LocationData? _lastPosition;
  DateTime? _lastUpdateTime;
  final Duration _updateInterval = Duration(seconds: 30); // Updated to 30 seconds
  final double _distanceThreshold = 50; // 50 meters threshold
  StreamSubscription<LocationData>? _locationSubscription;

  void startBroadcastingLocation() {
    if (_locationSubscription != null) {
      print("Broadcast already started.");
      return;
    }
    print("Location Broadcast Service Starting");

    _locationSubscription = locationProvider.getLocationStream().listen(
          (position) {
        // Update currentPosition in the LocationProvider
        locationProvider.updateCurrentPosition(position);

        if (_shouldUpdateLocation(position)) {
          roomProvider.updateRooms(position);
          _lastPosition = position;
          _lastUpdateTime = DateTime.now();
        }
      },
      onError: (e) {
        print('Error in location stream: $e');
      },
    );
  }

  void stopBroadcastingLocation() {
    print("Stopping broadcast location service.");
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  bool _shouldUpdateLocation(LocationData position) {
    if (_lastPosition == null || _lastUpdateTime == null) return true;

    final distance = _calculateDistance(
      _lastPosition!.latitude!,
      _lastPosition!.longitude!,
      position.latitude!,
      position.longitude!,
    );
    final timeElapsed = DateTime.now().difference(_lastUpdateTime!);

    print('Time elapsed: ${timeElapsed.inSeconds}s, Distance moved: $distance meters');

    // Update only if more than 30 seconds have passed AND moved more than 50 meters
    return timeElapsed > _updateInterval && distance > _distanceThreshold;
  }

  double _calculateDistance(
      double startLatitude,
      double startLongitude,
      double endLatitude,
      double endLongitude) {
    const earthRadius = 6371000; // in meters
    final dLat = _degreesToRadians(endLatitude - startLatitude);
    final dLon = _degreesToRadians(endLongitude - startLongitude);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(startLatitude)) *
            cos(_degreesToRadians(endLatitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distance = earthRadius * c;
    return distance;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  LocationData? getLastKnownPosition() {
    return _lastPosition;
  }
}
