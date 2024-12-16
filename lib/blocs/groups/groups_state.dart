import 'package:equatable/equatable.dart';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/models/grid_user.dart';

abstract class GroupsState extends Equatable {
  const GroupsState();

  @override
  List<Object> get props => [];
}

class GroupsInitial extends GroupsState {}

class GroupsLoading extends GroupsState {}

class GroupsError extends GroupsState {
  final String message;
  const GroupsError(this.message);

  @override
  List<Object> get props => [message];
}

class GroupsLoaded extends GroupsState {
  final List<Room> groups;
  final String? selectedRoomId;
  final List<GridUser>? selectedRoomMembers;
  final Map<String, String>? membershipStatuses;

  const GroupsLoaded(
      this.groups, {
        this.selectedRoomId,
        this.selectedRoomMembers,
        this.membershipStatuses,
      });

  GroupsLoaded copyWith({
    List<Room>? groups,
    String? selectedRoomId,
    List<GridUser>? selectedRoomMembers,
    Map<String, String>? membershipStatuses,
  }) {
    return GroupsLoaded(
      groups ?? this.groups,
      selectedRoomId: selectedRoomId ?? this.selectedRoomId,
      selectedRoomMembers: selectedRoomMembers ?? this.selectedRoomMembers,
      membershipStatuses: membershipStatuses ?? this.membershipStatuses,
    );
  }

  // Create a new instance with cleared member data but keeping groups
  GroupsLoaded clearMemberData() {
    return GroupsLoaded(
      groups,
      selectedRoomId: null,
      selectedRoomMembers: null,
      membershipStatuses: null,
    );
  }

  // Check if member data is loaded
  bool get hasMemberData => selectedRoomId != null &&
      selectedRoomMembers != null &&
      membershipStatuses != null;

  // Get member status safely
  String getMemberStatus(String userId) {
    return membershipStatuses?[userId] ?? 'join';
  }

  @override
  List<Object> get props => [
    groups,
    if (selectedRoomId != null) selectedRoomId!,
    if (selectedRoomMembers != null) selectedRoomMembers!,
    if (membershipStatuses != null) membershipStatuses!,
  ];

  @override
  String toString() {
    return 'GroupsLoaded(groups: ${groups.length}, selectedRoomId: $selectedRoomId, '
        'memberCount: ${selectedRoomMembers?.length})';
  }
}