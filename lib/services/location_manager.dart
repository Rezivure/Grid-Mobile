import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:latlong2/latlong.dart';

class LocationManager with ChangeNotifier {
  final StreamController<bg.Location> _locationStreamController = StreamController.broadcast();

  bg.Location? _lastPosition;
  DateTime? _lastUpdateTime;
  bool _isTracking = false;
  bool _isInForeground = true;
  bool _isMoving = false;

  // Timing configurations
  final Duration _foregroundInterval = const Duration(seconds: 30);
  final Duration _backgroundMovingInterval = const Duration(minutes: 1);
  final Duration _backgroundStationary = const Duration(minutes: 5);
  final Duration _terminatedInterval = const Duration(minutes: 15);

  late final AppLifecycleListener _lifecycleListener;

  LocationManager() {
    _initializeLifecycleListener();
  }

  void _initializeLifecycleListener() {
    _lifecycleListener = AppLifecycleListener(
        onStateChange: (state) {
          switch (state) {
            case AppLifecycleState.resumed:
              print("Grid: App in foreground");
              _isInForeground = true;
              _updateTrackingConfig();
              break;
            case AppLifecycleState.paused:
            case AppLifecycleState.inactive:
            case AppLifecycleState.detached:
              print("Grid: App in background");
              _isInForeground = false;
              _updateTrackingConfig();
              break;
            default:
              break;
          }
        }
    );
  }

  void _updateTrackingConfig() {
    if (!_isTracking) return;

    if (_isInForeground) {
      print("Grid: Applying foreground config");
      bg.BackgroundGeolocation.setConfig(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 0, // Important: Allow all movement updates
        locationUpdateInterval: _foregroundInterval.inMilliseconds,
        fastestLocationUpdateInterval: (_foregroundInterval.inMilliseconds / 2).round(),
        disableStopDetection: true,
        stopTimeout: 0,
        isMoving: true, // Force movement detection in foreground
        pausesLocationUpdatesAutomatically: false,
      ));
    } else {
      print("Grid: Applying background config");
      final interval = _isMoving ? _backgroundMovingInterval : _backgroundStationary;
      bg.BackgroundGeolocation.setConfig(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_MEDIUM,
        distanceFilter: 10, // Minimum distance (meters) before an update
        locationUpdateInterval: interval.inMilliseconds,
        fastestLocationUpdateInterval: interval.inMilliseconds,
        pausesLocationUpdatesAutomatically: true,
      ));
    }
  }

  Stream<bg.Location> get locationStream => _locationStreamController.stream;

  LatLng? get currentLatLng {
    if (_lastPosition == null) return null;
    final coords = _lastPosition!.coords;
    return LatLng(coords.latitude, coords.longitude);
  }

  bool get isTracking => _isTracking;

  Future<void> startTracking() async {
    if (_isTracking) {
      print("Grid: Location tracking already started.");
      return;
    }

    print("Grid: Initializing LocationManager...");

    // Request required permissions first
    if (Platform.isIOS) {
      await bg.BackgroundGeolocation.requestPermission();
    }

    await bg.BackgroundGeolocation.ready(bg.Config(
      // Basic Configuration
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 0,
        stopOnTerminate: false,
        startOnBoot: true,
        enableHeadless: false,

        // iOS Specific
        activityType: bg.Config.ACTIVITY_TYPE_OTHER, // Don't tie to specific activity type
        pausesLocationUpdatesAutomatically: false,

        // Motion Activity Settings
        isMoving: true, // Start assuming movement
        stopTimeout: 0, // Disable stop detection timeout
        motionTriggerDelay: 0, // Disable motion trigger delay

        // Background Operation
        backgroundPermissionRationale: bg.PermissionRationale(
            title: "Allow Grid to access location in background?",
            message: "Grid needs your location in background to keep your trusted contacts updated.",
            positiveAction: "Allow",
            negativeAction: "Cancel"
        ),

        // Notification Configuration
        notification: bg.Notification(
          title: "Grid Location Sharing",
          text: "Sharing your location with trusted contacts",
          sticky: true,
        ),

        // Debug Settings
        debug: false,
        logLevel: bg.Config.LOG_LEVEL_ERROR
    ));

    _setupEventListeners();

    await bg.BackgroundGeolocation.start();
    _isTracking = true;
    _updateTrackingConfig(); // Apply initial configuration
  }

  void _setupEventListeners() {
    // Regular location updates
    bg.BackgroundGeolocation.onLocation((bg.Location location) {
      print("Grid: Location update - speed: ${location.coords.speed?.toStringAsFixed(2) ?? 'unknown'} m/s");

      // Update motion state based on speed (walking speed ~1.4 m/s)
      if (location.coords.speed != null && location.coords.speed! > 1.4) {
        _isMoving = true;
        print("Grid: Movement detected - speed: ${location.coords.speed} m/s");
      }

      _processLocation(location);
    });

    // Provider changes (location services status)
    bg.BackgroundGeolocation.onProviderChange((bg.ProviderChangeEvent event) {
      print("Grid: Location provider changed - $event");
      if (event.status == bg.ProviderChangeEvent.AUTHORIZATION_STATUS_ALWAYS) {
        startTracking();
      }
    });

    // Motion state changes
    bg.BackgroundGeolocation.onMotionChange((bg.Location location) {
      final isMoving = location.isMoving ?? false;
      print("Grid: Motion state changed - Moving: $isMoving");
      _isMoving = isMoving;
      _updateTrackingConfig();
      _processLocation(location);
    });

    // Activity changes
    bg.BackgroundGeolocation.onActivityChange((bg.ActivityChangeEvent event) {
      print("Grid: Activity changed - ${event.activity} (${event.confidence}%)");
      if (event.confidence >= 75) {
        _isMoving = event.activity != 'still';
        _updateTrackingConfig();
      }
    });
  }

  void stopTracking() {
    if (!_isTracking) {
      print("Grid: Location tracking is not active.");
      return;
    }

    print("Grid: Stopping LocationManager...");
    bg.BackgroundGeolocation.stop();
    bg.BackgroundGeolocation.removeListeners();
    _isTracking = false;
  }

  void _processLocation(bg.Location location) {
    if (!_shouldUpdateLocation(location)) {
      print("Grid: Skipping update due to throttling");
      return;
    }

    final currentCoords = location.coords;
    print("Grid: Processing location update (${_isInForeground ? 'Foreground' : 'Background'}, Moving: $_isMoving)");

    _lastPosition = location;
    _lastUpdateTime = DateTime.now();

    _locationStreamController.add(location);
    notifyListeners();
  }

  bool _shouldUpdateLocation(bg.Location location) {
    if (_lastPosition == null || _lastUpdateTime == null) return true;

    final timeElapsed = DateTime.now().difference(_lastUpdateTime!);

    // Always update in foreground according to interval
    if (_isInForeground) {
      return timeElapsed > _foregroundInterval;
    }

    // In background, use appropriate interval based on motion state
    final relevantInterval = _isMoving ? _backgroundMovingInterval : _backgroundStationary;
    return timeElapsed > relevantInterval;
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _locationStreamController.close();
    stopTracking();
    super.dispose();
  }
}