import 'dart:async';
import 'dart:io' show Platform;
import 'package:libre_location/libre_location.dart' as libre;
import 'location_service.dart';
import 'location_update.dart';
import 'location_service_config.dart';

/// Implementation of LocationService using the libre_location plugin.
///
/// Uses the preset-based API (`LibreLocation.start(preset:, config:)`) so the
/// plugin's AutoAdapter handles iOS foreground/background lifecycle transitions
/// and activity-based adaptation automatically.
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
      final preset = _presetForMode(_config.mode);
      final locationConfig = _buildStartConfig(_config);

      // Use preset API so AutoAdapter manages iOS background survival
      await libre.LibreLocation.start(preset: preset, config: locationConfig);
      
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
      print("✓ Location tracking started successfully (preset: $preset)");
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
      await libre.LibreLocation.stop();
      
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
        final preset = _presetForMode(config.mode);
        await libre.LibreLocation.setPreset(preset);
        print("✓ Location preset updated to $preset");
      } catch (e) {
        print("✗ Error updating location preset: $e");
        throw e;
      }
    }
  }

  /// Maps a TrackingMode to the corresponding libre_location preset.
  libre.TrackingPreset _presetForMode(TrackingMode mode) {
    switch (mode) {
      case TrackingMode.batterySaver:
        return libre.TrackingPreset.low;
      default:
        return libre.TrackingPreset.balanced;
    }
  }

  /// Builds the LocationConfig for `LibreLocation.start()`.
  ///
  /// Only sets platform/notification options — the preset controls all
  /// accuracy, interval, and motion-detection parameters via AutoAdapter.
  libre.LocationConfig _buildStartConfig(LocationServiceConfig config) {
    return libre.LocationConfig(
      stopOnTerminate: false,
      startOnBoot: config.startOnBoot,
      enableHeadless: config.enableHeadless,
      notification: libre.NotificationConfig(
        title: "Location Sharing",
        text: "Active",
        sticky: true,
        priority: libre.NotificationPriority.low,
      ),
      backgroundPermissionRationale: libre.PermissionRationale(
        title: "Allow background location?",
        message: "This app utilizes location data which is end-to-end encrypted and only shared with your chosen contacts.",
        positiveAction: "Allow",
        negativeAction: "Cancel",
      ),
      debug: false,
    );
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

  void dispose() {
    if (_isTracking) {
      stop();
    }
    _locationStreamController.close();
    _motionChangeStreamController.close();
  }
}
