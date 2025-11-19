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
      // Battery saver config - balanced between battery and reliability
      bg.BackgroundGeolocation.setConfig(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_MEDIUM, // Medium accuracy for balance
        distanceFilter: 200, // Reduced from 500 to 200m
        stopTimeout: 10, // Increased from 5 to 10 minutes
        disableStopDetection: false,
        pausesLocationUpdatesAutomatically: true,
        stationaryRadius: 75, // Reduced from 100 to 75m
        heartbeatInterval: 1200, // 20 minutes (works in background)
        activityRecognitionInterval: 20000, // Check activity less frequently (20s)
        minimumActivityRecognitionConfidence: 80, // Higher confidence required
        disableMotionActivityUpdates: false,
        stopDetectionDelay: 10, // Increased from 5 to 10 minutes
      ));
    } else {
      // Normal config - more aggressive to prevent stopping
      if (_isInForeground) {
        bg.BackgroundGeolocation.setConfig(bg.Config(
          desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
          distanceFilter: 10,
          disableStopDetection: false,
          pausesLocationUpdatesAutomatically: true,
          stopTimeout: 5, // Increased from 2 to 5 minutes
          heartbeatInterval: 300, // 5 minutes in foreground
          activityRecognitionInterval: 10000, // 10s in foreground
          minimumActivityRecognitionConfidence: 70,
          stopDetectionDelay: 2, // Increased from 1 to 2 minutes
        ));
      } else {
        bg.BackgroundGeolocation.setConfig(bg.Config(
          desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH, // HIGH accuracy even in background
          distanceFilter: 50, // Reduced from 100 to 50m for more frequent updates
          stopTimeout: 5, // Increased from 3 to 5 minutes
          disableStopDetection: false,
          pausesLocationUpdatesAutomatically: true,
          stationaryRadius: 50, // Reduced from 75 to 50m
          heartbeatInterval: 1200, // 20 minutes in background (works even when app suspended)
          activityRecognitionInterval: 15000, // 15s in background
          minimumActivityRecognitionConfidence: 75,
          stopDetectionDelay: 5, // Increased from 3 to 5 minutes
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

    // Configure plugin one time with more aggressive defaults to prevent stopping
    await bg.BackgroundGeolocation.ready(bg.Config(
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      stopOnTerminate: false,
      startOnBoot: true,
      enableHeadless: false,
      disableStopDetection: false,
      activityType: bg.Config.ACTIVITY_TYPE_OTHER,
      stopTimeout: 5, // Increased from 2 to 5 minutes
      stopDetectionDelay: 2, // Increased from 1 to 2 minutes
      // Motion detection optimizations
      isMoving: false, // Start in stationary mode
      motionTriggerDelay: 0, // No delay for motion trigger
      disableMotionActivityUpdates: false,
      useSignificantChangesOnly: false,
      // Heartbeat for stationary updates (this works in background on iOS/Android)
      heartbeatInterval: 1200, // 20 minutes - guaranteed update even when stationary and backgrounded
      // Power optimizations
      preventSuspend: false, // Allow OS to suspend when possible
      disableLocationAuthorizationAlert: false,
      locationAuthorizationRequest: 'Always',
      backgroundPermissionRationale: bg.PermissionRationale(
        title: "Allow background location?",
        message: "This app utilizes location data which is end-to-end encrypted and only shared with your chosen contacts.",
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

    // Location updates - always keep position fresh
    bg.BackgroundGeolocation.onLocation((bg.Location location) {
      final now = DateTime.now();
      
      // Always update our internal position to keep it fresh
      _lastPosition = location;
      
      // Smart throttling: Only skip SENDING updates if stationary and recent
      if (!_isMoving && _lastLocationUpdate != null) {
        final timeSinceLastUpdate = now.difference(_lastLocationUpdate!);

        // Reduced throttling intervals for more frequent updates
        final throttleInterval = _batterySaverEnabled
            ? const Duration(minutes: 3) // Reduced from 5 to 3 minutes
            : const Duration(seconds: 30); // Reduced from 1 minute to 30 seconds

        if (timeSinceLastUpdate < throttleInterval) {
          print("Throttling location broadcast - stationary and recent update exists");
          return; // Skip broadcasting, but we've already updated _lastPosition
        }
      }
      
      // Broadcast the update
      _lastLocationUpdate = now;
      _locationStreamController.add(location);
      notifyListeners();
    });

    // Motion-detection updates
    bg.BackgroundGeolocation.onMotionChange((bg.Location location) {
      print(">>> onMotionChange: isMoving = ${location.isMoving}");
      _isMoving = location.isMoving ?? false;
      
      // Always update position from motion change event
      _lastPosition = location;
      
      // If started moving, immediately broadcast the update
      if (_isMoving) {
        _lastLocationUpdate = DateTime.now();
        _locationStreamController.add(location);
        notifyListeners();
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
  // This ALWAYS gets a fresh location, bypassing any throttling
  Future<void> grabLocationAndPing() async {
    try {
      print("Manually requesting current location...");
      final currentPos = await bg.BackgroundGeolocation.getCurrentPosition(
        samples: 3, // Take multiple samples for better accuracy on manual ping
        timeout: 30,
        maximumAge: 0, // Force fresh location
        persist: false,
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH, // Force high accuracy for manual ping
      );
      
      // Always update position and timestamp for manual requests
      _lastPosition = currentPos;
      _lastLocationUpdate = DateTime.now();
      _locationStreamController.add(currentPos);
      notifyListeners();
      
      print("Manual location ping completed: ${currentPos.coords.latitude}, ${currentPos.coords.longitude}");
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
