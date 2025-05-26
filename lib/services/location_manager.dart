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
  bool _isMoving = false;
  DateTime? _lastLocationUpdate;

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
      // Battery saver config - more aggressive battery saving
      bg.BackgroundGeolocation.setConfig(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_LOW, // Lower accuracy saves more battery
        distanceFilter: 500, // Only update after 500m movement
        stopTimeout: 5, // Wait longer before entering stationary mode
        disableStopDetection: false,
        pausesLocationUpdatesAutomatically: true,
        stationaryRadius: 100, // Larger radius to prevent false movement detection
        heartbeatInterval: 1800, // 30 min heartbeat
        activityRecognitionInterval: 20000, // Check activity less frequently (20s)
        minimumActivityRecognitionConfidence: 80, // Higher confidence required
        disableMotionActivityUpdates: false,
        stopDetectionDelay: 5, // Wait 5 min before stopping
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
          activityRecognitionInterval: 10000, // 10s in foreground
          minimumActivityRecognitionConfidence: 70,
          stopDetectionDelay: 1, // Quick stop detection in foreground
        ));
      } else {
        bg.BackgroundGeolocation.setConfig(bg.Config(
          desiredAccuracy: bg.Config.DESIRED_ACCURACY_MEDIUM, // Medium accuracy in background
          distanceFilter: 100,
          stopTimeout: 3,
          disableStopDetection: false,
          pausesLocationUpdatesAutomatically: true,
          stationaryRadius: 75,
          heartbeatInterval: 600, // 10 min
          activityRecognitionInterval: 15000, // 15s in background
          minimumActivityRecognitionConfidence: 75,
          stopDetectionDelay: 3, // 3 min delay in background
          disableMotionActivityUpdates: false,
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
  bool get batterySaverEnabled => _batterySaverEnabled;
  bool get isMoving => _isMoving;
  DateTime? get lastLocationUpdate => _lastLocationUpdate;
  
  // Check if location data is stale
  bool get isLocationStale {
    if (_lastLocationUpdate == null) return true;
    final age = DateTime.now().difference(_lastLocationUpdate!);
    return age > const Duration(minutes: 10);
  }
  
  // Get age of last location update
  Duration? get locationAge {
    if (_lastLocationUpdate == null) return null;
    return DateTime.now().difference(_lastLocationUpdate!);
  }

  // Start tracking. Let the plugin handle moving vs stationary automatically.
  Future<void> startTracking() async {
    if (_isTracking) return;

    // Request permission (especially for iOS)
    if (Platform.isIOS) {
      await bg.BackgroundGeolocation.requestPermission();
    }

    // Configure plugin one time with optimized defaults
    await bg.BackgroundGeolocation.ready(bg.Config(
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      stopOnTerminate: false,
      startOnBoot: true,
      enableHeadless: true,
      disableStopDetection: false,
      activityType: bg.Config.ACTIVITY_TYPE_OTHER,
      stopTimeout: 2,
      stopDetectionDelay: 1,
      // Motion detection optimizations
      isMoving: false, // Start in stationary mode
      motionTriggerDelay: 0, // No delay for motion trigger
      disableMotionActivityUpdates: false,
      useSignificantChangesOnly: false,
      // Power optimizations
      preventSuspend: false, // Allow OS to suspend when possible
      disableLocationAuthorizationAlert: false,
      locationAuthorizationRequest: 'Always',
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
        priority: bg.Config.NOTIFICATION_PRIORITY_LOW, // Lower priority notification
      ),
      debug: false,
      logLevel: bg.Config.LOG_LEVEL_ERROR, // Reduce logging overhead
      maxDaysToPersist: 1, // Reduce storage
      maxRecordsToPersist: 20, // Reduce storage
    ));

    // Location updates with smart throttling
    bg.BackgroundGeolocation.onLocation((bg.Location location) {
      final now = DateTime.now();
      
      // Smart throttling: Skip updates if stationary and recent update exists
      if (!_isMoving && _lastLocationUpdate != null) {
        final timeSinceLastUpdate = now.difference(_lastLocationUpdate!);
        
        // In battery saver mode, throttle stationary updates more aggressively
        final throttleInterval = _batterySaverEnabled 
            ? const Duration(minutes: 5) 
            : const Duration(minutes: 1);
            
        if (timeSinceLastUpdate < throttleInterval) {
          print("Skipping location update - stationary and recent update exists");
          return;
        }
      }
      
      _lastPosition = location;
      _lastLocationUpdate = now;
      _locationStreamController.add(location);
      notifyListeners();
    });

    // Motion-detection updates
    bg.BackgroundGeolocation.onMotionChange((bg.Location location) {
      print(">>> onMotionChange: isMoving = ${location.isMoving}");
      _isMoving = location.isMoving ?? false;
      
      // If started moving, immediately get a location update
      if (_isMoving) {
        bg.BackgroundGeolocation.getCurrentPosition(
          samples: 1,
          persist: false,
        ).then((pos) {
          _lastPosition = pos;
          _lastLocationUpdate = DateTime.now();
          _locationStreamController.add(pos);
          notifyListeners();
        });
      }
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
