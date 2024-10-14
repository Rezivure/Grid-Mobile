import 'package:flutter/material.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/providers/room_provider.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/providers/location_provider.dart';


class LocationTrackingService {
  final DatabaseService databaseService;
  final RoomProvider roomProvider;
  final LocationProvider locationProvider; // Add LocationProvider here

  LocationTrackingService(this.databaseService, this.roomProvider, this.locationProvider);

  Timer? _timer;
  final Duration updateInterval = Duration(seconds: 30);

  void startService() {
    print("Location Tracking Service Starting");
    // do initial push and pull
    final position = locationProvider.currentPosition;
    if (position != null) {
      roomProvider.updateRooms(position);  // Use the position to update rooms
    } else {
      print('No current position available');
    }
    roomProvider.fetchAndUpdateLocations();


    _timer = Timer.periodic(updateInterval, (Timer t) => periodicLocationTasks());
  }

  void stopService() {
    print("Location Tracking Service Stopping");
    _timer?.cancel();
  }

  Future<void> periodicLocationTasks() async {
    final position = locationProvider.currentPosition;
    if (position != null) {
      roomProvider.updateRooms(position);  // Use the position to update rooms
    } else {
      print('No current position available');
    }
    roomProvider.fetchAndUpdateLocations();
  }

  Future<Map<String, Map<String, dynamic>>> getMostRecentLocations() async {
    final locations = await databaseService.getUserLocations();
    Map<String, Map<String, dynamic>> userLocationMap = {};

    for (final location in locations) {
      final userId = location['userId'] as String;
      final latitude = location['latitude'] as double;
      final longitude = location['longitude'] as double;
      final timestamp = location['timestamp'] as String;

      userLocationMap[userId] = {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp,
      };
    }

    return userLocationMap;
  }
}
