import 'package:equatable/equatable.dart';

abstract class MapEvent extends Equatable {
  const MapEvent();

  @override
  List<Object?> get props => [];
}

class MapInitialize extends MapEvent {}

class MapCenterOnUser extends MapEvent {}

class MapMoveToUser extends MapEvent {
  final String userId;
  const MapMoveToUser(this.userId);

  @override
  List<Object?> get props => [userId];
}

class MapLoadUserLocations extends MapEvent {}

class RemoveUserLocation extends MapEvent {
  final String userId;
  const RemoveUserLocation(this.userId);
}
