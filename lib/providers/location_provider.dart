import 'dart:async';
import 'package:flutter/material.dart';
import 'package:location/location.dart';

enum TrackingMode {
  batterySaver,
  normal,
  aggressive,
}

class LocationProvider with ChangeNotifier {
  final Location _location = Location();
  LocationData? _currentPosition;
  StreamSubscription<LocationData>? _locationSubscription;
  TrackingMode _trackingMode = TrackingMode.normal;

  LocationData? get currentPosition => _currentPosition;

  TrackingMode get trackingMode => _trackingMode;

  set trackingMode(TrackingMode mode) {
    _trackingMode = mode;
    stopLocationTracking();
    startLocationTracking();
  }

  void updateCurrentPosition(LocationData position) {
    _currentPosition = position;
    print('Updated currentPosition in LocationProvider: Lat: ${position.latitude}, Long: ${position.longitude}');
    notifyListeners();
  }

  Future<void> determinePosition() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }
    }

    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted &&
          permissionGranted != PermissionStatus.grantedLimited) {
        throw Exception('Location permissions are denied');
      }
    }

    await _location.enableBackgroundMode(enable: true);

    _currentPosition = await _location.getLocation();
    notifyListeners();
  }

  void startLocationTracking() {
    LocationSettings settings;

    switch (_trackingMode) {
      case TrackingMode.batterySaver:
        settings = LocationSettings(
          interval: 15 * 60 * 1000, // 15 minutes
          distanceFilter: 100,
          accuracy: LocationAccuracy.low,
        );
        break;
      case TrackingMode.normal:
        settings = LocationSettings(
          interval: 3 * 60 * 1000, // 3 minutes in milliseconds
          distanceFilter: 50, // 50 meters
          accuracy: LocationAccuracy.balanced,
        );
        break;
      case TrackingMode.aggressive:
        settings = LocationSettings(
          interval: 30 * 1000, // 30 seconds in milliseconds
          distanceFilter: 50, // 50 meters
          accuracy: LocationAccuracy.high,
        );
        break;
    }

    _location.changeSettings(
      interval: settings.interval,
      distanceFilter: settings.distanceFilter,
      accuracy: settings.accuracy,
    );

    _locationSubscription = _location.onLocationChanged.listen(
          (LocationData position) {
        _currentPosition = position;
        print('Updated currentPosition: $_currentPosition');
        notifyListeners();
      },
      onError: (e) {
        print('Error in getting location: $e');
      },
    );
  }

  void stopLocationTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  Stream<LocationData> getLocationStream() {
    return _location.onLocationChanged;
  }

  @override
  void dispose() {
    stopLocationTracking();
    super.dispose();
  }
}

class LocationSettings {
  final int interval;
  final double distanceFilter;
  final LocationAccuracy accuracy;

  LocationSettings({
    required this.interval,
    required this.distanceFilter,
    required this.accuracy,
  });
}
