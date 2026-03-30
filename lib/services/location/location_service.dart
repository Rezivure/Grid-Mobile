import 'location_update.dart';
import 'location_service_config.dart';

/// Abstract interface for location services.
/// This isolates the app from any specific location plugin implementation.
abstract class LocationService {
  /// Stream of location updates.
  Stream<LocationUpdate> get locationStream;

  /// Stream of motion state changes (true = moving, false = stationary).
  Stream<bool> get motionChangeStream;

  /// Start location tracking.
  Future<void> start();

  /// Stop location tracking.
  Future<void> stop();

  /// Get the current position immediately.
  Future<LocationUpdate> getCurrentPosition();

  /// Request location permissions.
  Future<bool> requestPermission();

  /// Update the tracking configuration.
  Future<void> setConfig(LocationServiceConfig config);

  /// Whether location tracking is currently active.
  bool get isTracking;
}