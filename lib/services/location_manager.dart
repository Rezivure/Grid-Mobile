import 'dart:async';
import 'dart:math';
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
  final Duration _foregroundInterval = const Duration(seconds: 30);      // Active app usage
  final Duration _backgroundMovingInterval = const Duration(minutes: 1); // Moving in background
  final Duration _backgroundStationary = const Duration(minutes: 5);     // Stationary in background
  final Duration _terminatedInterval = const Duration(minutes: 15);      // App terminated

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
        locationUpdateInterval: _foregroundInterval.inMilliseconds,
        fastestLocationUpdateInterval: (_foregroundInterval.inMilliseconds / 2).round(),
        // Ensure updates in foreground regardless of motion
        disableStopDetection: true,
      ));
    } else {
      print("Grid: Applying background config");
      final interval = _isMoving ? _backgroundMovingInterval : _backgroundStationary;
      bg.BackgroundGeolocation.setConfig(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_MEDIUM,
        locationUpdateInterval: interval.inMilliseconds,
        fastestLocationUpdateInterval: interval.inMilliseconds,
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
    await bg.BackgroundGeolocation.ready(bg.Config(
      // Location Settings
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,

        // Force periodic updates regardless of motion
        disableStopDetection: _isInForeground,  // Disable in foreground for constant updates

        // Activity Recognition
        isMoving: true,
        stopTimeout: 5,
        activityRecognitionInterval: 10000,

        // Background/Terminated Behavior
        stopOnTerminate: false,  // Continue tracking after termination
        startOnBoot: true,      // Restart tracking on device reboot
        enableHeadless: false,  // No headless mode needed

        // iOS specific
        stationaryRadius: 200.0,  // iOS stationary geofence radius in meters

        // Motion detection settings
        motionTriggerDelay: 30000,  // 30 second delay to confirm movement
        minimumActivityRecognitionConfidence: 75,

        // Periodic updates
        heartbeatInterval: _terminatedInterval.inMinutes,

        // Notification settings
        notification: bg.Notification(
          title: "Grid Location Sharing",
          text: "Sharing your location with trusted contacts",
          sticky: true,
        ),

        preventSuspend: false,
        debug: false,
        logLevel: bg.Config.LOG_LEVEL_ERROR
    ));

    _setupEventListeners();

    if (Platform.isIOS) {
      // Ensure proper permissions on iOS
      bg.BackgroundGeolocation.requestPermission();
    }

    bg.BackgroundGeolocation.start();
    _isTracking = true;
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

    // Provider changes (location services status)
    bg.BackgroundGeolocation.onProviderChange((bg.ProviderChangeEvent event) {
      print("Grid: Location provider changed - $event");
      if (event.status == bg.ProviderChangeEvent.AUTHORIZATION_STATUS_ALWAYS) {
        startTracking();
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

    // In foreground, always update every 30 seconds
    if (_isInForeground) {
      print("Grid: Foreground update check - Time elapsed: ${timeElapsed.inSeconds}s");
      return timeElapsed > _foregroundInterval;
    }

    // In background:
    // If moving, update every 1 minute
    if (_isMoving && timeElapsed > _backgroundMovingInterval) {
      return true;
    }

    // Always update every 5 minutes regardless of motion
    return timeElapsed > _backgroundStationary;
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _locationStreamController.close();
    stopTracking();
    super.dispose();
  }
}