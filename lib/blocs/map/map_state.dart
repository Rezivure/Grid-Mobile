import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import 'package:grid_frontend/models/user_location.dart';

class MapState extends Equatable {
  final bool isLoading;
  final LatLng? center;
  final double zoom;
  final List<UserLocation> userLocations;
  final String? error;
  final int moveCount;
  final String? selectedUserId;


  const MapState({
    this.isLoading = true,
    this.center,
    this.zoom = 16.0,
    this.userLocations = const [],
    this.error,
    this.moveCount = 0,
    this.selectedUserId,
  });

  MapState copyWith({
    bool? isLoading,
    LatLng? center,
    double? zoom,
    List<UserLocation>? userLocations,
    String? error,
    int? moveCount,
    String? selectedUserId,
    bool clearSelectedUserId = false,
  }) {
    return MapState(
      isLoading: isLoading ?? this.isLoading,
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
      userLocations: userLocations ?? this.userLocations,
      error: error,
      moveCount: moveCount ?? this.moveCount,
      selectedUserId: clearSelectedUserId ? null : (selectedUserId ?? this.selectedUserId),
    );
  }

  @override
  List<Object?> get props => [isLoading, center, zoom, userLocations, error, moveCount, selectedUserId];
}
