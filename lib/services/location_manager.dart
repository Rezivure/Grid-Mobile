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

  bg.Location? get lastPosition => _lastPosition;


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
              _isInForeground = true;
              _updateTrackingConfig();
              break;
            case AppLifecycleState.paused:
            case AppLifecycleState.inactive:
            case AppLifecycleState.detached:
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
      bg.BackgroundGeolocation.setConfig(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        locationUpdateInterval: _foregroundInterval.inMilliseconds,
        fastestLocationUpdateInterval: (_foregroundInterval.inMilliseconds / 2).round(),
      ));
    } else {
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
    if (_isTracking) return;

    await bg.BackgroundGeolocation.ready(bg.Config(
      // Location Settings
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,

        // Activity Recognition
        isMoving: true,
        stopTimeout: 5,
        activityRecognitionInterval: 10000,

        // Background/Terminated Behavior
        stopOnTerminate: false,
        startOnBoot: true,
        enableHeadless: false,

        // iOS specific
        stationaryRadius: 200.0,

        // Motion detection settings
        motionTriggerDelay: 30000,
        minimumActivityRecognitionConfidence: 75,

        // Update intervals
        heartbeatInterval: Platform.isIOS ? 60 : _terminatedInterval.inMinutes,

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
      await bg.BackgroundGeolocation.requestPermission();
    }

    await bg.BackgroundGeolocation.start();
    _isTracking = true;
  }

  void _setupEventListeners() {
    bg.BackgroundGeolocation.onLocation((bg.Location location) {
      if (location.coords.speed != null && location.coords.speed! > 1.4) {
        _isMoving = true;
      }
      _processLocation(location);
    });

    bg.BackgroundGeolocation.onMotionChange((bg.Location location) {
      _isMoving = location.isMoving ?? false;
      _updateTrackingConfig();
      _processLocation(location);
    });

    bg.BackgroundGeolocation.onActivityChange((bg.ActivityChangeEvent event) {
      if (event.confidence >= 75) {
        _isMoving = event.activity != 'still';
        _updateTrackingConfig();
      }
    });

    bg.BackgroundGeolocation.onProviderChange((bg.ProviderChangeEvent event) {
      if (event.status == bg.ProviderChangeEvent.AUTHORIZATION_STATUS_ALWAYS) {
        startTracking();
      }
    });
  }

  void stopTracking() {
    if (!_isTracking) return;

    bg.BackgroundGeolocation.stop();
    bg.BackgroundGeolocation.removeListeners();
    _isTracking = false;
  }

  void _processLocation(bg.Location location) {
    if (!_shouldUpdateLocation(location)) return;

    _lastPosition = location;
    _lastUpdateTime = DateTime.now();

    _locationStreamController.add(location);
    notifyListeners();
  }

  bool _shouldUpdateLocation(bg.Location location) {
    if (_lastPosition == null || _lastUpdateTime == null) return true;

    final timeElapsed = DateTime.now().difference(_lastUpdateTime!);

    // In foreground, always update every 30 seconds regardless of motion
    if (_isInForeground) {
      return timeElapsed > _foregroundInterval;
    }

    // In background, use motion-based intervals
    final updateInterval = _isMoving ? _backgroundMovingInterval : _backgroundStationary;
    return timeElapsed > updateInterval;
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _locationStreamController.close();
    stopTracking();
    super.dispose();
  }
}