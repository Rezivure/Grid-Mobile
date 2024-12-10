import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:latlong2/latlong.dart';

class LocationManager with ChangeNotifier {
  final StreamController<bg.Location> _locationStreamController = StreamController.broadcast();

  bg.Location? _lastPosition;
  DateTime? _lastUpdateTime;
  bool _isTracking = false;
  final Duration _updateInterval = const Duration(seconds: 30);
  final double _distanceThreshold = 50;

  /// Expose the location stream for listeners
  Stream<bg.Location> get locationStream => _locationStreamController.stream;

  /// Getter to return the current position as LatLng
  LatLng? get currentLatLng {
    if (_lastPosition == null) return null;
    final coords = _lastPosition!.coords;
    return LatLng(coords.latitude, coords.longitude);
  }

  bool get isTracking => _isTracking;

  /// Start tracking location
  Future<void> startTracking() async {
    if (_isTracking) {
      print("Location tracking already started.");
      return;
    }

    print("Initializing and starting LocationManager...");
    await bg.BackgroundGeolocation.ready(bg.Config(
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      distanceFilter: 10.0,
      stopOnTerminate: false,
      startOnBoot: true,
      debug: false,
      logLevel: bg.Config.LOG_LEVEL_VERBOSE,
    ));

    bg.BackgroundGeolocation.start();
    _isTracking = true;

    // Listen to location updates
    bg.BackgroundGeolocation.onLocation((bg.Location location) {
      _processLocation(location);
    });

    // Listen to motion changes
    bg.BackgroundGeolocation.onMotionChange((bg.Location location) {
      _processLocation(location);
    });

    // Listen to provider changes
    bg.BackgroundGeolocation.onProviderChange((bg.ProviderChangeEvent event) {
      print('[providerchange] - $event');
    });
  }

  /// Stop tracking location
  void stopTracking() {
    if (!_isTracking) {
      print("Location tracking is not active.");
      return;
    }

    print("Stopping LocationManager...");
    bg.BackgroundGeolocation.stop();
    bg.BackgroundGeolocation.removeListeners();
    _isTracking = false;
  }

  /// Process location update
  void _processLocation(bg.Location location) {
    final currentCoords = location.coords;

    if (_shouldUpdateLocation(location)) {
      print("Processing location: $currentCoords");
      _lastPosition = location;
      _lastUpdateTime = DateTime.now();

      // Broadcast location update
      _locationStreamController.add(location);

      notifyListeners();
    }
  }

  /// Check if location update should be processed
  bool _shouldUpdateLocation(bg.Location location) {
    if (_lastPosition == null || _lastUpdateTime == null) return true;

    final lastCoords = _lastPosition!.coords;
    final currentCoords = location.coords;

    final distance = _calculateDistance(
      lastCoords.latitude,
      lastCoords.longitude,
      currentCoords.latitude,
      currentCoords.longitude,
    );
    final timeElapsed = DateTime.now().difference(_lastUpdateTime!);

    print("Time elapsed: ${timeElapsed.inSeconds}s, Distance moved: $distance meters");
    return timeElapsed > _updateInterval && distance > _distanceThreshold;
  }

  /// Calculate distance between two coordinates
  double _calculateDistance(
      double startLatitude, double startLongitude, double endLatitude, double endLongitude) {
    const earthRadius = 6371000; // in meters
    final dLat = _degreesToRadians(endLatitude - startLatitude);
    final dLon = _degreesToRadians(endLongitude - startLongitude);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(startLatitude)) *
            cos(_degreesToRadians(endLatitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  @override
  void dispose() {
    _locationStreamController.close();
    stopTracking();
    super.dispose();
  }
}
