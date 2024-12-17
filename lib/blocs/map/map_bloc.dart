import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/blocs/map/map_state.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/models/user_location.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  final LocationManager locationManager;
  final LocationRepository locationRepository;
  final DatabaseService databaseService;
  late final StreamSubscription<UserLocation> _locationSubscription;


  MapBloc({
    required this.locationManager,
    required this.locationRepository,
    required this.databaseService,
  }) : super(const MapState()) {
    on<MapInitialize>(_onMapInitialize);
    on<MapCenterOnUser>(_onMapCenterOnUser);
    on<MapMoveToUser>(_onMapMoveToUser);
    on<MapLoadUserLocations>(_onMapLoadUserLocations);
    on<RemoveUserLocation>(_onRemoveUserLocation);

  _locationSubscription = locationRepository.locationUpdates.listen(_onLocationUpdate);
}

  @override
  Future<void> close() {
    _locationSubscription.cancel();
    return super.close();
  }

  void _onLocationUpdate(UserLocation location) {
    // Update the state with the new or updated location
    final updatedLocations = List<UserLocation>.from(state.userLocations);
    final index = updatedLocations.indexWhere((loc) => loc.userId == location.userId);

    if (index != -1) {
      updatedLocations[index] = location; // Update existing location
    } else {
      updatedLocations.add(location); // Add new location
    }

    emit(state.copyWith(userLocations: updatedLocations));
  }

  Future<void> _onMapInitialize(MapInitialize event,
      Emitter<MapState> emit) async {
    // Load initial data if needed, for example:
    // Maybe load user locations right away
    add(MapLoadUserLocations());
    emit(state.copyWith(isLoading: false));
  }

  void _onRemoveUserLocation(RemoveUserLocation event, Emitter<MapState> emit) {
    print("MapBloc: Removing location for user: ${event.userId}");
    final updatedLocations = state.userLocations
        .where((location) => location.userId != event.userId)
        .toList();
    print("MapBloc: Locations before: ${state.userLocations.length}, after: ${updatedLocations.length}");
    emit(state.copyWith(userLocations: updatedLocations));
  }

  Future<void> _onMapCenterOnUser(MapCenterOnUser event,
      Emitter<MapState> emit) async {
    final currentPosition = locationManager.currentLatLng;
    if (currentPosition != null) {
      final userLocation = LatLng(
          currentPosition.latitude!, currentPosition.longitude!);
      emit(state.copyWith(center: userLocation));
    } else {
      emit(state.copyWith(error: 'No user location available'));
    }
  }

  Future<void> _onMapMoveToUser(MapMoveToUser event, Emitter<MapState> emit) async {
    try {
      // Add small delay to let any pending updates finish
      await Future.delayed(const Duration(milliseconds: 100));

      final userLocationData = await locationRepository.getLatestLocationFromHistory(event.userId);

      if (userLocationData != null) {
        print("New center: ${userLocationData.position}");

        // Force map update with two-step emit
        emit(state.copyWith(center: null));
        emit(state.copyWith(
            center: userLocationData.position,
            isLoading: false
        ));
      } else {
        print("Latest location not available for user");
        emit(state.copyWith(error: 'Location not available for this user.'));
      }
    } catch (e) {
      print("Error moving to user: $e");
      emit(state.copyWith(error: 'Error moving to user location: $e'));
    }
  }

  Future<void> _onMapLoadUserLocations(MapLoadUserLocations event, Emitter<MapState> emit) async {
    try {
      final latestLocations = await locationRepository.getAllLatestLocations();

      emit(state.copyWith(
          isLoading: false,
          userLocations: latestLocations
      ));
    } catch (e) {
      emit(state.copyWith(error: 'Error loading user locations: $e'));
    }
  }
}