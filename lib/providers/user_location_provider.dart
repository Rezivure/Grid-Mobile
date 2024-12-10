import 'package:flutter/material.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/repositories/location_repository.dart';

class UserLocationProvider with ChangeNotifier {
  final Map<String, UserLocation> _userLocations = {};
  final LocationRepository locationRepository;

  UserLocationProvider(this.locationRepository) {
    _initializeLocations();
    _listenForDatabaseUpdates();
  }

  Future<void> _initializeLocations() async {
    final locations = await locationRepository.getAllLocations();
    for (var location in locations) {
      _userLocations[location.userId] = location;
    }
    notifyListeners();
  }

  void _listenForDatabaseUpdates() {
    locationRepository.locationUpdates.listen((location) {
      _userLocations[location.userId] = location;
      notifyListeners();
    });
  }

  List<UserLocation> getAllUserLocations() => _userLocations.values.toList();

  UserLocation? getUserLocation(String userId) {
    return _userLocations[userId];
  }

  void updateUserLocation(UserLocation location) {
    _userLocations[location.userId] = location;
    notifyListeners();
  }

  // Get the last seen time for a user
  String? getLastSeen(String userId) {
    final location = _userLocations[userId];
    return location?.timestamp;
  }

  void clearAllLocations() {
    _userLocations.clear();
    notifyListeners();
  }
}
