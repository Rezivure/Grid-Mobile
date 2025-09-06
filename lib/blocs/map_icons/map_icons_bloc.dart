import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/blocs/map_icons/map_icons_event.dart';
import 'package:grid_frontend/blocs/map_icons/map_icons_state.dart';
import 'package:grid_frontend/models/map_icon.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/services/database_service.dart';

class MapIconsBloc extends Bloc<MapIconsEvent, MapIconsState> {
  final MapIconRepository _mapIconRepository;

  MapIconsBloc({
    MapIconRepository? mapIconRepository,
  })  : _mapIconRepository = mapIconRepository ?? MapIconRepository(DatabaseService()),
        super(const MapIconsState()) {
    on<LoadMapIcons>(_onLoadMapIcons);
    on<LoadMapIconsForRooms>(_onLoadMapIconsForRooms);
    on<MapIconCreated>(_onMapIconCreated);
    on<MapIconUpdated>(_onMapIconUpdated);
    on<MapIconDeleted>(_onMapIconDeleted);
    on<MapIconsBulkUpdate>(_onMapIconsBulkUpdate);
    on<ClearMapIconsForRoom>(_onClearMapIconsForRoom);
    on<ClearAllMapIcons>(_onClearAllMapIcons);
  }

  Future<void> _onLoadMapIcons(
    LoadMapIcons event,
    Emitter<MapIconsState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, selectedRoomId: event.roomId));
      final icons = await _mapIconRepository.getIconsForRoom(event.roomId);
      emit(state.copyWith(
        icons: icons,
        isLoading: false,
        error: null,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to load icons: $e',
      ));
    }
  }

  Future<void> _onLoadMapIconsForRooms(
    LoadMapIconsForRooms event,
    Emitter<MapIconsState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, selectedRoomIds: event.roomIds));
      final icons = await _mapIconRepository.getIconsForRooms(event.roomIds);
      emit(state.copyWith(
        icons: icons,
        isLoading: false,
        error: null,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to load icons: $e',
      ));
    }
  }

  Future<void> _onMapIconCreated(
    MapIconCreated event,
    Emitter<MapIconsState> emit,
  ) async {
    try {
      // Check if icon already exists
      final existingIndex = state.icons.indexWhere((icon) => icon.id == event.icon.id);
      if (existingIndex >= 0) {
        print('[MapIconsBloc] Icon ${event.icon.id} already exists, skipping');
        return;
      }

      // Add the new icon to the list
      final updatedIcons = List<MapIcon>.from(state.icons)..add(event.icon);
      emit(state.copyWith(icons: updatedIcons));
      
      print('[MapIconsBloc] Icon ${event.icon.id} added to state');
    } catch (e) {
      print('[MapIconsBloc] Error adding icon: $e');
    }
  }

  Future<void> _onMapIconUpdated(
    MapIconUpdated event,
    Emitter<MapIconsState> emit,
  ) async {
    try {
      // Find and update the icon
      final updatedIcons = state.icons.map((icon) {
        if (icon.id == event.icon.id) {
          return event.icon;
        }
        return icon;
      }).toList();

      emit(state.copyWith(icons: updatedIcons));
      
      print('[MapIconsBloc] Icon ${event.icon.id} updated in state');
    } catch (e) {
      print('[MapIconsBloc] Error updating icon: $e');
    }
  }

  Future<void> _onMapIconDeleted(
    MapIconDeleted event,
    Emitter<MapIconsState> emit,
  ) async {
    try {
      // Remove the icon from the list
      final updatedIcons = state.icons
          .where((icon) => icon.id != event.iconId)
          .toList();

      emit(state.copyWith(icons: updatedIcons));
      
      print('[MapIconsBloc] Icon ${event.iconId} removed from state');
    } catch (e) {
      print('[MapIconsBloc] Error deleting icon: $e');
    }
  }

  Future<void> _onMapIconsBulkUpdate(
    MapIconsBulkUpdate event,
    Emitter<MapIconsState> emit,
  ) async {
    try {
      // Get existing icons not in this room
      final otherIcons = state.icons
          .where((icon) => icon.roomId != event.roomId)
          .toList();
      
      // Combine with new icons for this room
      final updatedIcons = [...otherIcons, ...event.icons];
      
      emit(state.copyWith(icons: updatedIcons));
      
      print('[MapIconsBloc] Bulk update: ${event.icons.length} icons for room ${event.roomId}');
    } catch (e) {
      print('[MapIconsBloc] Error in bulk update: $e');
    }
  }

  Future<void> _onClearMapIconsForRoom(
    ClearMapIconsForRoom event,
    Emitter<MapIconsState> emit,
  ) async {
    try {
      // Remove all icons for the specified room
      final updatedIcons = state.icons
          .where((icon) => icon.roomId != event.roomId)
          .toList();

      emit(state.copyWith(icons: updatedIcons));
      
      print('[MapIconsBloc] Cleared icons for room ${event.roomId}');
    } catch (e) {
      print('[MapIconsBloc] Error clearing icons: $e');
    }
  }

  Future<void> _onClearAllMapIcons(
    ClearAllMapIcons event,
    Emitter<MapIconsState> emit,
  ) async {
    emit(state.copyWith(icons: []));
    print('[MapIconsBloc] Cleared all icons');
  }
}