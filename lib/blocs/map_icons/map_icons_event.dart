import 'package:equatable/equatable.dart';
import 'package:grid_frontend/models/map_icon.dart';

abstract class MapIconsEvent extends Equatable {
  const MapIconsEvent();

  @override
  List<Object?> get props => [];
}

/// Load all icons for a specific room
class LoadMapIcons extends MapIconsEvent {
  final String roomId;

  const LoadMapIcons(this.roomId);

  @override
  List<Object?> get props => [roomId];
}

/// Load icons for multiple rooms (groups view)
class LoadMapIconsForRooms extends MapIconsEvent {
  final List<String> roomIds;

  const LoadMapIconsForRooms(this.roomIds);

  @override
  List<Object?> get props => [roomIds];
}

/// Icon was created (locally or remotely)
class MapIconCreated extends MapIconsEvent {
  final MapIcon icon;

  const MapIconCreated(this.icon);

  @override
  List<Object?> get props => [icon];
}

/// Icon was updated (locally or remotely)
class MapIconUpdated extends MapIconsEvent {
  final MapIcon icon;

  const MapIconUpdated(this.icon);

  @override
  List<Object?> get props => [icon];
}

/// Icon was deleted (locally or remotely)
class MapIconDeleted extends MapIconsEvent {
  final String iconId;
  final String roomId;

  const MapIconDeleted({required this.iconId, required this.roomId});

  @override
  List<Object?> get props => [iconId, roomId];
}

/// Bulk update of icons (from state event)
class MapIconsBulkUpdate extends MapIconsEvent {
  final List<MapIcon> icons;
  final String roomId;

  const MapIconsBulkUpdate({required this.icons, required this.roomId});

  @override
  List<Object?> get props => [icons, roomId];
}

/// Clear all icons for a room
class ClearMapIconsForRoom extends MapIconsEvent {
  final String roomId;

  const ClearMapIconsForRoom(this.roomId);

  @override
  List<Object?> get props => [roomId];
}

/// Clear all icons
class ClearAllMapIcons extends MapIconsEvent {}