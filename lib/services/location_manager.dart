import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location/location_service.dart';
import 'location/location_update.dart';
import 'location/location_service_config.dart';
import 'location/libre_location_service.dart';

/// A simpler location manager relying on the plugin's own stop-detection.
/// Battery Saver Mode slightly changes the config, otherwise we let
/// the plugin handle moving vs stationary. Includes a `grabLocationAndPing`
/// method for manual location fetch/ping.
class LocationManager with ChangeNotifier {
  final StreamController<LocationUpdate> _locationStreamController = StreamController.broadcast();
  final LocationService _locationService = LibreLocationService();

  LocationUpdate? _lastPosition;
  bool _isTracking = false;
  bool _isInForeground = true;
  bool _batterySaverEnabled = false;
  bool _isMoving = false;
  DateTime? _lastLocationUpdate;

  late final AppLifecycleListener _lifecycleListener;
  StreamSubscription<LocationUpdate>? _locationSubscription;
  StreamSubscription<bool>? _motionSubscription;

  LocationManager() {
    _initializeLifecycleListener();
    _loadBatterySaverState();
    _setupLocationService();
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

  // Setup location service listeners
  void _setupLocationService() {
    // Listen for location updates
    _locationSubscription = _locationService.locationStream.listen((location) {
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

    // Listen for motion changes
    _motionSubscription = _locationService.motionChangeStream.listen((isMoving) {
      print(">>> Motion change: isMoving = $isMoving");
      _isMoving = isMoving;
      notifyListeners();
    });
  }

  // Apply the appropriate config based on battery-saver mode
  void _updateTrackingConfig() {
    if (!_isTracking) return;

    final mode = _batterySaverEnabled ? TrackingMode.batterySaver : TrackingMode.normal;
    final config = LocationServiceConfig(
      mode: mode,
      enableHeadless: true,
      startOnBoot: true,
    );
    
    _locationService.setConfig(config);
  }

  // Stream for listening to location updates in your UI
  Stream<LocationUpdate> get locationStream => _locationStreamController.stream;

  // Simple helper to get the last known LatLng
  LatLng? get currentLatLng {
    if (_lastPosition == null) return null;
    return LatLng(_lastPosition!.latitude, _lastPosition!.longitude);
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

    print("====== STARTING LOCATION TRACKING ======");

    // Request permissions
    final permissionGranted = await _locationService.requestPermission();
    if (!permissionGranted) {
      print("✗ ERROR: Location permission denied!");
      print("  → Please enable location permissions in device settings");
      return;
    }

    // Start the location service
    await _locationService.start();
    _isTracking = true;

    // Apply battery-saver/foreground/background config
    _updateTrackingConfig();
    notifyListeners();
  }

  // Manually request the current location (e.g., for a "Ping" button)
  // This ALWAYS gets a fresh location, bypassing any throttling
  Future<void> grabLocationAndPing() async {
    try {
      final currentPos = await _locationService.getCurrentPosition();
      
      // Always update position and timestamp for manual requests
      _lastPosition = currentPos;
      _lastLocationUpdate = DateTime.now();
      _locationStreamController.add(currentPos);
      notifyListeners();
      
      print("Manual location ping completed: ${currentPos.latitude}, ${currentPos.longitude}");
    } catch (e) {
      print("Error getting current position: $e");
    }
  }

  // Stop tracking and remove listeners
  Future<void> stopTracking() async {
    if (!_isTracking) return;
    await _locationService.stop();
    _isTracking = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _locationSubscription?.cancel();
    _motionSubscription?.cancel();
    if (_isTracking) {
      _locationService.stop();
      _isTracking = false;
    }
    final service = _locationService;
    if (service is LibreLocationService) {
      service.dispose();
    }
    _locationStreamController.close();
    super.dispose();
  }
}
