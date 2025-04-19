import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A simpler location manager relying on the plugin's own stop-detection.
/// Battery Saver Mode slightly changes the config, otherwise we let
/// the plugin handle moving vs stationary. Includes a `grabLocationAndPing`
/// method for manual location fetch/ping.
class LocationManager with ChangeNotifier {
  final StreamController<bg.Location> _locationStreamController = StreamController.broadcast();

  bg.Location? _lastPosition;
  bool _isTracking = false;
  bool _isInForeground = true;
  bool _batterySaverEnabled = false;

  late final AppLifecycleListener _lifecycleListener;

  LocationManager() {
    _initializeLifecycleListener();
    _loadBatterySaverState();
  }

  // Listen for app foreground/background changes
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
      },
    );
  }

  // Restore battery-saver setting from SharedPreferences
  Future<void> _loadBatterySaverState() async {
    final prefs = await SharedPreferences.getInstance();
    _batterySaverEnabled = prefs.getBool('battery_saver') ?? false;
  }

  // Toggle battery-saver mode
  Future<void> toggleBatterySaverMode(bool enabled) async {
    _batterySaverEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('battery_saver', enabled);
    _updateTrackingConfig();
    notifyListeners();
  }

  // Apply the appropriate config based on battery-saver + foreground/background
  void _updateTrackingConfig() {
    if (!_isTracking) return;

    if (_batterySaverEnabled) {
      // Battery saver config
      bg.BackgroundGeolocation.setConfig(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_MEDIUM,
        distanceFilter: 200,
        stopTimeout: 2,
        disableStopDetection: false,
        pausesLocationUpdatesAutomatically: true,
        stationaryRadius: 50,
        heartbeatInterval: 900, // 15 min
      ));
    } else {
      // Normal config
      if (_isInForeground) {
        bg.BackgroundGeolocation.setConfig(bg.Config(
          desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
          distanceFilter: 10,
          disableStopDetection: false,
          pausesLocationUpdatesAutomatically: true,
          stopTimeout: 2,
          heartbeatInterval: 60, // 1 min
        ));
      } else {
        bg.BackgroundGeolocation.setConfig(bg.Config(
          desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
          distanceFilter: 100,
          stopTimeout: 2,
          disableStopDetection: false,
          pausesLocationUpdatesAutomatically: true,
          stationaryRadius: 50,
          heartbeatInterval: 600, // 10 min
        ));
      }
    }
  }

  // Stream for listening to location updates in your UI
  Stream<bg.Location> get locationStream => _locationStreamController.stream;

  // Simple helper to get the last known LatLng
  LatLng? get currentLatLng {
    if (_lastPosition == null) return null;
    return LatLng(_lastPosition!.coords.latitude, _lastPosition!.coords.longitude);
  }

  bool get isTracking => _isTracking;

  // Start tracking. Let the plugin handle moving vs stationary automatically.
  Future<void> startTracking() async {
    if (_isTracking) return;

    // Request permission (especially for iOS)
    if (Platform.isIOS) {
      await bg.BackgroundGeolocation.requestPermission();
    }

    // Configure plugin one time
    await bg.BackgroundGeolocation.ready(bg.Config(
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      stopOnTerminate: false,
      startOnBoot: true,
      enableHeadless: true,
      disableStopDetection: false,
      activityType: bg.Config.ACTIVITY_TYPE_OTHER,
      stopTimeout: 2,
      // If you want it to transition to stationary quickly, keep this low
      stopDetectionDelay: 0,
      backgroundPermissionRationale: bg.PermissionRationale(
        title: "Allow background location?",
        message: "Needed to keep sharing location with your contacts, even if app is closed.",
        positiveAction: "Allow",
        negativeAction: "Cancel",
      ),
      notification: bg.Notification(
        title: "Location Sharing",
        text: "Active",
        sticky: true,
      ),
      debug: false,
      logLevel: bg.Config.LOG_LEVEL_VERBOSE,
      maxDaysToPersist: 3,
      maxRecordsToPersist: 50,
    ));

    // Location updates
    bg.BackgroundGeolocation.onLocation((bg.Location location) {
      _lastPosition = location;
      _locationStreamController.add(location);
      notifyListeners();
    });

    // Motion-detection updates
    bg.BackgroundGeolocation.onMotionChange((bg.Location location) {
      print(">>> onMotionChange: isMoving = ${location.isMoving}");
      // Plugin decides if device is moving or stationary automatically.
    });

    // Start tracking
    await bg.BackgroundGeolocation.start();
    _isTracking = true;

    // Apply battery-saver/foreground/background config
    _updateTrackingConfig();
    notifyListeners();
  }

  // Manually request the current location (e.g., for a "Ping" button)
  Future<void> grabLocationAndPing() async {
    try {
      print("Manually requesting current location...");
      final currentPos = await bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1,
        timeout: 30,
        maximumAge: 0,
        persist: false,
      );
      _lastPosition = currentPos;
      _locationStreamController.add(currentPos);
      notifyListeners();
    } catch (e) {
      print("Error getting current position: $e");
    }
  }

  // Stop tracking and remove listeners
  Future<void> stopTracking() async {
    if (!_isTracking) return;
    await bg.BackgroundGeolocation.removeListeners();
    await bg.BackgroundGeolocation.stop();
    _isTracking = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    if (_isTracking) {
      bg.BackgroundGeolocation.removeListeners();
      bg.BackgroundGeolocation.stop();
      _isTracking = false;
    }
    _locationStreamController.close();
    super.dispose();
  }
}
