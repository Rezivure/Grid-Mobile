import 'dart:async';
import 'dart:io' show Platform;
import 'package:libre_location/libre_location.dart' as libre;
import 'location_service.dart';
import 'location_update.dart';
import 'location_service_config.dart';

/// Implementation of LocationService using the libre_location plugin.
class LibreLocationService implements LocationService {
  final StreamController<LocationUpdate> _locationStreamController = StreamController.broadcast();
  final StreamController<bool> _motionChangeStreamController = StreamController.broadcast();

  StreamSubscription<libre.Position>? _positionSubscription;
  StreamSubscription<libre.Position>? _motionSubscription;
  
  bool _isTracking = false;
  LocationServiceConfig _config = const LocationServiceConfig();

  @override
  Stream<LocationUpdate> get locationStream => _locationStreamController.stream;

  @override
  Stream<bool> get motionChangeStream => _motionChangeStreamController.stream;

  @override
  bool get isTracking => _isTracking;

  @override
  Future<void> start() async {
    if (_isTracking) return;

    print("====== STARTING LIBRE LOCATION TRACKING ======");

    try {
      // Start location tracking with the current config
      await libre.LibreLocation.startTracking(_buildLocationConfig(_config));
      
      // Listen for location updates
      _positionSubscription = libre.LibreLocation.positionStream.listen((position) {
        final locationUpdate = _mapPositionToLocationUpdate(position);
        _locationStreamController.add(locationUpdate);
      });

      // Listen for motion changes
      _motionSubscription = libre.LibreLocation.motionChangeStream.listen((position) {
        print(">>> Motion change: isMoving = ${position.isMoving}");
        _motionChangeStreamController.add(position.isMoving);
        
        // Also emit location update on motion change
        final locationUpdate = _mapPositionToLocationUpdate(position);
        _locationStreamController.add(locationUpdate);
      });

      _isTracking = true;
      print("✓ Location tracking started successfully");
    } catch (e) {
      print("✗ Error starting location tracking: $e");
      throw e;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isTracking) return;

    print("====== STOPPING LIBRE LOCATION TRACKING ======");

    try {
      await libre.LibreLocation.stopTracking();
      
      await _positionSubscription?.cancel();
      await _motionSubscription?.cancel();
      _positionSubscription = null;
      _motionSubscription = null;
      
      _isTracking = false;
      print("✓ Location tracking stopped successfully");
    } catch (e) {
      print("✗ Error stopping location tracking: $e");
      throw e;
    }
  }

  @override
  Future<LocationUpdate> getCurrentPosition() async {
    try {
      print("Manually requesting current position...");
      final position = await libre.LibreLocation.getCurrentPosition(
        accuracy: libre.Accuracy.high,
        samples: 3,
        timeout: 30,
        maximumAge: 0,
        persist: false,
      );
      
      final locationUpdate = _mapPositionToLocationUpdate(position);
      print("Manual location ping completed: ${locationUpdate.latitude}, ${locationUpdate.longitude}");
      return locationUpdate;
    } catch (e) {
      print("Error getting current position: $e");
      throw e;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      print("Requesting location permissions...");
      final permission = await libre.LibreLocation.requestPermission();
      print("Permission status: $permission");
      
      switch (permission) {
        case libre.LocationPermission.always:
        case libre.LocationPermission.whileInUse:
          return true;
        case libre.LocationPermission.denied:
        case libre.LocationPermission.deniedForever:
          print("✗ ERROR: Location permission denied!");
          return false;
      }
    } catch (e) {
      print("Error requesting permissions: $e");
      return false;
    }
  }

  @override
  Future<void> setConfig(LocationServiceConfig config) async {
    _config = config;
    
    if (_isTracking) {
      try {
        await libre.LibreLocation.setConfig(_buildLocationConfig(config));
        print("✓ Location config updated");
      } catch (e) {
        print("✗ Error updating location config: $e");
        throw e;
      }
    }
  }

  /// Maps libre_location Position to our platform-agnostic LocationUpdate.
  LocationUpdate _mapPositionToLocationUpdate(libre.Position position) {
    return LocationUpdate(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      altitude: position.altitude,
      timestamp: position.timestamp,
      isMoving: position.isMoving,
    );
  }

  /// Builds the libre_location LocationConfig from our simplified config.
  libre.LocationConfig _buildLocationConfig(LocationServiceConfig config) {
    // Create notification config for persistent tracking
    final notificationConfig = libre.NotificationConfig(
      title: "Location Sharing",
      text: "Active",
      sticky: true,
      priority: libre.NotificationPriority.low,
    );

    // Create background permission rationale
    final permissionRationale = libre.PermissionRationale(
      title: "Allow background location?",
      message: "This app utilizes location data which is end-to-end encrypted and only shared with your chosen contacts.",
      positiveAction: "Allow",
      negativeAction: "Cancel",
    );

    if (config.mode == TrackingMode.batterySaver) {
      // Battery saver config - balanced between battery and reliability
      return libre.LocationConfig(
        accuracy: libre.Accuracy.balanced,
        distanceFilter: 200,
        mode: libre.TrackingMode.balanced,
        intervalMs: 120000, // 2 minutes
        stopTimeout: 10,
        stationaryRadius: 75,
        heartbeatInterval: 1200, // 20 minutes
        activityRecognitionInterval: 20000,
        minimumActivityRecognitionConfidence: 80,
        stopDetectionDelay: 10,
        stopOnTerminate: false,
        startOnBoot: config.startOnBoot,
        enableHeadless: config.enableHeadless,
        enableMotionDetection: true,
        disableStopDetection: false,
        locationAuthorizationRequest: libre.LocationAuthorizationRequest.always,
        notification: notificationConfig,
        backgroundPermissionRationale: permissionRationale,
        debug: false,
        logLevel: libre.LogLevel.error,
        maxDaysToPersist: 1,
        maxRecordsToPersist: 20,
      );
    } else {
      // Normal config - more aggressive to prevent stopping
      return libre.LocationConfig(
        accuracy: libre.Accuracy.high,
        distanceFilter: 50,
        mode: libre.TrackingMode.active,
        intervalMs: 60000, // 1 minute
        stopTimeout: 5,
        stationaryRadius: 50,
        heartbeatInterval: 1200, // 20 minutes (works in background)
        activityRecognitionInterval: 15000,
        minimumActivityRecognitionConfidence: 75,
        stopDetectionDelay: 5,
        stopOnTerminate: false,
        startOnBoot: config.startOnBoot,
        enableHeadless: config.enableHeadless,
        enableMotionDetection: true,
        disableStopDetection: false,
        locationAuthorizationRequest: libre.LocationAuthorizationRequest.always,
        notification: notificationConfig,
        backgroundPermissionRationale: permissionRationale,
        debug: false,
        logLevel: libre.LogLevel.error,
        maxDaysToPersist: 1,
        maxRecordsToPersist: 20,
      );
    }
  }

  void dispose() {
    if (_isTracking) {
      stop();
    }
    _locationStreamController.close();
    _motionChangeStreamController.close();
  }
}