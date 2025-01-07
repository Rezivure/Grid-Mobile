import 'package:flutter/material.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';

class UserLocationProvider with ChangeNotifier {
  final Map<String, UserLocation> _userLocations = {};
  final LocationRepository locationRepository;
  final UserRepository userRepository;

  UserLocationProvider(this.locationRepository, this.userRepository) {
    _initializeLocations();
    _listenForDatabaseUpdates();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });

  }


  Future<void> _initializeLocations() async {
    final locations = await locationRepository.getAllLatestLocations(); // Use getAllLatestLocations instead
    for (var location in locations) {
      _userLocations[location.userId] = location;
    }
    notifyListeners();
  }

  // Modify getLastSeen to return the most recent timestamp
  String? getLastSeen(String userId) {
    final location = _userLocations[userId];
    if (location == null || location.timestamp == null) return null;

    // Ensure the timestamp is valid
    try {
      DateTime.parse(location.timestamp!);
      return location.timestamp;
    } catch (e) {
      print("Invalid timestamp for user $userId: ${location.timestamp}");
      return null;
    }
  }

  void _listenForDatabaseUpdates() {
    locationRepository.locationUpdates.listen((location) async {
      try {
        // Check if user exists in any rooms before updating location
        final userRooms = await userRepository.getUserRooms(location.userId);
        final directRoom = await userRepository.getDirectRoomForContact(location.userId);

        if (userRooms.isNotEmpty || directRoom != null) {
          _userLocations[location.userId] = location;
          notifyListeners();
        } else {
          // If user doesn't exist in any rooms, remove from cache
          _userLocations.remove(location.userId);
          notifyListeners();
        }
      } catch (e) {
        print("Error in location update listener: $e");
      }
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

  void debugUserLocations() {
    print("DEBUG _userLocations: ${_userLocations.keys.toList()}");
  }

  void removeUserLocation(String userId) {
    _userLocations.remove(userId);
    notifyListeners();
  }

  void clearAllLocations() {
    _userLocations.clear();
    notifyListeners();
  }
}
