import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationManager with ChangeNotifier {
  final StreamController<bg.Location> _locationStreamController = StreamController.broadcast();

  bg.Location? _lastPosition;
  DateTime? _lastUpdateTime;
  bool _isTracking = false;
  bool _isInForeground = true;
  bool _isMoving = false;
  bool _batterySaverEnabled = false;


  late final AppLifecycleListener _lifecycleListener;

  LocationManager() {
    _initializeLifecycleListener();
    _loadBatterySaverState();
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

  void _loadBatterySaverState() async {
    final prefs = await SharedPreferences.getInstance();
    _batterySaverEnabled = prefs.getBool('battery_saver') ?? false;
  }

  void toggleBatterySaverMode(bool value) {
    _batterySaverEnabled = value;
    _updateTrackingConfig();
  }
  void _updateTrackingConfig() {
    print("Updating Tracking Config");
    if (!_isTracking) return;

    if (_batterySaverEnabled) {
      print("Grid: Applying battery saver config");
      bg.BackgroundGeolocation.setConfig(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_MEDIUM,
        distanceFilter: 200,
        stopTimeout: 1,
        disableStopDetection: false,
        pausesLocationUpdatesAutomatically: true,
      ));
    }

    else if (_isInForeground) {
      print("Grid: Applying foreground config");
      bg.BackgroundGeolocation.setConfig(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 1,
        disableStopDetection: true,
        pausesLocationUpdatesAutomatically: false,
        isMoving: true, // Force movement detection in foreground

      ));
    } else {
      print("Grid: Applying background config");
      bg.BackgroundGeolocation.setConfig(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 50,
        stopTimeout: 3,
        pausesLocationUpdatesAutomatically: true,
        disableStopDetection: false,
        stationaryRadius: 50,
        isMoving: _isMoving,
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
        stopOnTerminate: false,
        startOnBoot: true,
        enableHeadless: true,
        heartbeatInterval: 900,
        disableStopDetection: false,

        // iOS Specific
        activityType: bg.Config.ACTIVITY_TYPE_OTHER,
        // Motion Activity Settings
        stopTimeout: 2,
        motionTriggerDelay: 15000,

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
  }

  Future<void> stopTracking() async {  // Make async
    if (!_isTracking) {
      print("Grid: Location tracking is not active.");
      return;
    }

    print("Grid: Stopping LocationManager...");
    await bg.BackgroundGeolocation.removeListeners();
    await bg.BackgroundGeolocation.stop();
    try {
     // await bg.BackgroundGeolocation.stopBackgroundTask();
    } catch (e) {
      print("Grid: Error finishing background operations: $e");
    }
    _isTracking = false;
  }

  void _processLocation(bg.Location location) {
    final currentCoords = location.coords;
    print("Grid: Processing location update (${_isInForeground ? 'Foreground' : 'Background'}, Moving: $_isMoving)");
    _lastPosition = location;

    if (_shouldUpdateBuffer()) {
      _lastUpdateTime = DateTime.now();
      _locationStreamController.add(location);
      notifyListeners();
    } else {
      // wait
      print("Grid: Did not update...throttling.");
    }

  }

  bool _shouldUpdateBuffer() {
    final now = DateTime.now();
    if (_lastUpdateTime == null) {
      return true; // first time
    }

    final timeSinceLast = now.difference(_lastUpdateTime!);
    if (timeSinceLast.inSeconds < 5) {
      return false;
    }
    return true;
  }



  @override
  void dispose() async {
    _lifecycleListener.dispose();

    if (_isTracking) {
      await bg.BackgroundGeolocation.removeListeners();
      await bg.BackgroundGeolocation.stop();
      _isTracking = false;
    }

    try {
      await bg.BackgroundGeolocation.stop();
    } catch (e) {
      print("Grid: Error finishing background operations: $e");
    }
    // Close stream
    await _locationStreamController.close();

    super.dispose();
  }
}