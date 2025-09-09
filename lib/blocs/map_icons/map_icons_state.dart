import 'package:equatable/equatable.dart';
import 'package:grid_frontend/models/map_icon.dart';

class MapIconsState extends Equatable {
  final List<MapIcon> icons;
  final bool isLoading;
  final String? error;
  final String? selectedRoomId;
  final List<String>? selectedRoomIds;

  const MapIconsState({
    this.icons = const [],
    this.isLoading = false,
    this.error,
    this.selectedRoomId,
    this.selectedRoomIds,
  });

  /// Get icons filtered by current selection
  List<MapIcon> get filteredIcons {
    if (selectedRoomId != null) {
      return icons.where((icon) => icon.roomId == selectedRoomId).toList();
    } else if (selectedRoomIds != null && selectedRoomIds!.isNotEmpty) {
      return icons.where((icon) => selectedRoomIds!.contains(icon.roomId)).toList();
    }
    return icons;
  }

  MapIconsState copyWith({
    List<MapIcon>? icons,
    bool? isLoading,
    String? error,
    String? selectedRoomId,
    List<String>? selectedRoomIds,
  }) {
    return MapIconsState(
      icons: icons ?? this.icons,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      selectedRoomId: selectedRoomId ?? this.selectedRoomId,
      selectedRoomIds: selectedRoomIds ?? this.selectedRoomIds,
    );
  }

  @override
  List<Object?> get props => [icons, isLoading, error, selectedRoomId, selectedRoomIds];
}