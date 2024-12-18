import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';
import 'package:grid_frontend/blocs/groups/groups_state.dart';

class GroupsBloc extends Bloc<GroupsEvent, GroupsState> {
  final RoomService roomService;
  final RoomRepository roomRepository;
  final UserRepository userRepository;
  final LocationRepository locationRepository;
  final MapBloc mapBloc;
  List<Room> _allGroups = [];

  GroupsBloc({
    required this.roomService,
    required this.roomRepository,
    required this.userRepository,
    required this.mapBloc,
    required this.locationRepository,
  }) : super(GroupsInitial()) {
    on<LoadGroups>(_onLoadGroups);
    on<RefreshGroups>(_onRefreshGroups);
    on<DeleteGroup>(_onDeleteGroup);
    on<SearchGroups>(_onSearchGroups);
    on<UpdateGroup>(_onUpdateGroup);
    on<LoadGroupMembers>(_onLoadGroupMembers);
    on<UpdateMemberStatus>(_onUpdateMemberStatus);
  }

  Future<void> _onLoadGroups(LoadGroups event, Emitter<GroupsState> emit) async {
    emit(GroupsLoading());
    try {
      _allGroups = await _loadGroups();
      // Always emit a new instance of GroupsLoaded to force UI update
      emit(GroupsLoaded(List.from(_allGroups)));
    } catch (e) {
      print("GroupsBloc: Error loading groups - $e");
      emit(GroupsError(e.toString()));
    }
  }

  Future<void> _onRefreshGroups(RefreshGroups event, Emitter<GroupsState> emit) async {
    print("GroupsBloc: Handling RefreshGroups event");
    try {
      // First emit loading state to trigger UI update
      emit(GroupsLoading());

      final updatedGroups = await _loadGroups();
      _allGroups = updatedGroups;

      // Preserve member data if we have it
      if (state is GroupsLoaded) {
        final currentState = state as GroupsLoaded;
        emit(GroupsLoaded(
          List.from(_allGroups),
          selectedRoomId: currentState.selectedRoomId,
          selectedRoomMembers: currentState.selectedRoomMembers,
          membershipStatuses: currentState.membershipStatuses,
        ));
      } else {
        emit(GroupsLoaded(List.from(_allGroups)));
      }

      // Force another load to ensure UI updates
      add(LoadGroups());

    } catch (e) {
      print("GroupsBloc: Error in RefreshGroups - $e");
      emit(GroupsError(e.toString()));
    }
  }


  Future<void> _onDeleteGroup(DeleteGroup event, Emitter<GroupsState> emit) async {
    try {
      final room = await roomRepository.getRoomById(event.roomId);
      if (room != null) {
        final members = room.members;

        await roomService.leaveRoom(event.roomId);
        await roomRepository.deleteRoom(event.roomId);

        for (final memberId in members) {
          final userRooms = await roomRepository.getUserRooms(memberId);
          if (userRooms.isEmpty) {
            mapBloc.add(RemoveUserLocation(memberId));
          }
        }

        _allGroups = await _loadGroups();
        emit(GroupsLoaded(_allGroups));
      }
    } catch (e) {
      print("GroupsBloc: Error deleting group - $e");
      emit(GroupsError(e.toString()));
    }
  }

  void _onSearchGroups(SearchGroups event, Emitter<GroupsState> emit) {
    if (_allGroups.isEmpty) return;

    if (event.query.isEmpty) {
      if (state is GroupsLoaded) {
        final currentState = state as GroupsLoaded;
        emit(GroupsLoaded(
          _allGroups,
          selectedRoomId: currentState.selectedRoomId,
          selectedRoomMembers: currentState.selectedRoomMembers,
          membershipStatuses: currentState.membershipStatuses,
        ));
      } else {
        emit(GroupsLoaded(_allGroups));
      }
      return;
    }

    final searchTerm = event.query.toLowerCase();
    final filteredGroups = _allGroups.where((group) {
      return group.name.toLowerCase().contains(searchTerm);
    }).toList();

    if (state is GroupsLoaded) {
      final currentState = state as GroupsLoaded;
      emit(GroupsLoaded(
        filteredGroups,
        selectedRoomId: currentState.selectedRoomId,
        selectedRoomMembers: currentState.selectedRoomMembers,
        membershipStatuses: currentState.membershipStatuses,
      ));
    } else {
      emit(GroupsLoaded(filteredGroups));
    }
  }

  Future<void> _onUpdateGroup(UpdateGroup event, Emitter<GroupsState> emit) async {
    try {
      print("GroupsBloc: Handling UpdateGroup for room ${event.roomId}");
      final room = await roomRepository.getRoomById(event.roomId);
      if (room != null) {
        final index = _allGroups.indexWhere((g) => g.roomId == event.roomId);
        if (index != -1) {
          _allGroups[index] = room;
          if (state is GroupsLoaded) {
            final currentState = state as GroupsLoaded;

            // Get updated member data if this is the selected room
            if (currentState.selectedRoomId == event.roomId) {
              print("GroupsBloc: Updating members for selected room");
              final members = await userRepository.getGroupParticipants();
              final filteredMembers = members.where(
                      (user) => room.members.contains(user.userId)
              ).toList();

              // Get current membership statuses
              final Map<String, String> membershipStatuses =
              Map<String, String>.from(currentState.membershipStatuses ?? {});

              // Update status for each member
              await Future.wait(
                filteredMembers.map((user) async {
                  final status = await roomService.getUserRoomMembership(
                    event.roomId,
                    user.userId,
                  );
                  membershipStatuses[user.userId] = status ?? 'join';
                  print("GroupsBloc: Updated status for ${user.userId} to ${status ?? 'join'}");
                }),
              );

              print("GroupsBloc: Emitting new state with ${filteredMembers.length} members");
              emit(GroupsLoaded(
                List.from(_allGroups),
                selectedRoomId: currentState.selectedRoomId,
                selectedRoomMembers: filteredMembers,
                membershipStatuses: membershipStatuses,
              ));
            } else {
              // Just update the groups list if this isn't the selected room
              emit(GroupsLoaded(
                List.from(_allGroups),
                selectedRoomId: currentState.selectedRoomId,
                selectedRoomMembers: currentState.selectedRoomMembers,
                membershipStatuses: currentState.membershipStatuses,
              ));
            }
          } else {
            emit(GroupsLoaded(List.from(_allGroups)));
          }
        }
      }
    } catch (e) {
      print("GroupsBloc: Error updating group - $e");
    }
  }

  Future<void> _onLoadGroupMembers(
      LoadGroupMembers event,
      Emitter<GroupsState> emit,
      ) async {
    if (state is GroupsLoaded) {
      final currentState = state as GroupsLoaded;
      emit(GroupsLoaded(currentState.groups));
    }

    try {
      final room = await roomRepository.getRoomById(event.roomId);
      if (room == null) {
        throw Exception('Room not found');
      }

      // Get all relationships for this room
      final relationships = await userRepository.getUserRelationshipsForRoom(event.roomId);
      final memberIds = relationships.map((r) => r['userId'] as String).toSet();

      final members = await userRepository.getGroupParticipants();
      final filteredMembers = members.where(
              (user) => memberIds.contains(user.userId)
      ).toList();

      final Map<String, String> membershipStatuses = {};
      for (var relationship in relationships) {
        membershipStatuses[relationship['userId'] as String] =
            relationship['membershipStatus'] as String? ?? 'join';
      }

      if (state is GroupsLoaded) {
        final currentState = state as GroupsLoaded;
        emit(GroupsLoaded(
          currentState.groups,
          selectedRoomId: event.roomId,
          selectedRoomMembers: filteredMembers,
          membershipStatuses: membershipStatuses,
        ));
      }
    } catch (e) {
      print("Error in LoadGroupMembers: $e");
      emit(GroupsError(e.toString()));
    }
  }

  Future<void> _onUpdateMemberStatus(
      UpdateMemberStatus event,
      Emitter<GroupsState> emit,
      ) async {
    try {
      if (state is GroupsLoaded) {
        final currentState = state as GroupsLoaded;

        // Only update if we're viewing the relevant room
        if (currentState.selectedRoomId == event.roomId) {
          // Update the membership status
          final updatedStatuses = Map<String, String>.from(
            currentState.membershipStatuses ?? {},
          );
          updatedStatuses[event.userId] = event.status;

          // If the user just joined, we may need to update members list
          if (event.status == 'join') {
            final room = await roomRepository.getRoomById(event.roomId);
            if (room != null) {
              final members = await userRepository.getGroupParticipants();
              final filteredMembers = members.where(
                      (user) => room.members.contains(user.userId)
              ).toList();

              emit(GroupsLoaded(
                currentState.groups,
                selectedRoomId: event.roomId,
                selectedRoomMembers: filteredMembers,
                membershipStatuses: updatedStatuses,
              ));
            }
          } else {
            // Just update the status if not a join
            emit(currentState.copyWith(
              membershipStatuses: updatedStatuses,
            ));
          }
        }
      }
    } catch (e) {
      print("GroupsBloc: Error updating member status - $e");
    }
  }

  Future<void> handleMemberKicked(String roomId, String userId) async {
    print("Processing kick for user: $userId in room: $roomId");

    try {
      // Start with removing all user relationships
      await userRepository.removeUserRelationship(userId, roomId);

      // Get and update membership status to explicitly mark as left
      await userRepository.updateMembershipStatus(userId, roomId, 'leave');

      // Get the room
      final room = await roomRepository.getRoomById(roomId);
      if (room != null) {
        // Remove from room members list
        final updatedMembers = room.members.where((id) => id != userId).toList();
        final updatedRoom = Room(
          roomId: room.roomId,
          name: room.name,
          isGroup: room.isGroup,
          lastActivity: DateTime.now().toIso8601String(),
          avatarUrl: room.avatarUrl,
          members: updatedMembers,
          expirationTimestamp: room.expirationTimestamp,
        );

        // Update room in database
        await roomRepository.updateRoom(updatedRoom);

        // Explicitly remove from room participants
        await roomRepository.removeRoomParticipant(roomId, userId);

        // Get all relationships to check user's status
        final relationships = await userRepository.getUserRelationshipsForRoom(roomId);

        // Remove all traces of this user's relationship with this room
        for (var relationship in relationships) {
          if (relationship['userId'] == userId) {
            await userRepository.deleteUserRelationship(userId, roomId);
          }
        }

        // Check if user should be completely cleaned up
        final userRooms = await roomRepository.getUserRooms(userId);
        final directRoom = await userRepository.getDirectRoomForContact(userId);

        if (userRooms.isEmpty && directRoom == null) {
          print("User not in any rooms or contacts, cleaning up completely");
          await locationRepository.deleteUserLocations(userId);
          await userRepository.deleteUser(userId);
          mapBloc.add(RemoveUserLocation(userId));
        }

        // Force immediate UI updates
        add(LoadGroupMembers(roomId));
        add(RefreshGroups());

        // Add delayed updates to ensure sync
        Future.delayed(const Duration(milliseconds: 500), () {
          add(UpdateGroup(roomId));
          add(LoadGroups());
          add(LoadGroupMembers(roomId));
        });

        Future.delayed(const Duration(seconds: 1), () {
          add(RefreshGroups());
          add(LoadGroupMembers(roomId));
        });
      }
    } catch (e) {
      print("Error handling kicked member: $e");
      rethrow;
    }
  }

  Future<List<Room>> _loadGroups() async {
    final groups = await roomRepository.getNonExpiredRooms();
    groups.sort((a, b) =>
        DateTime.parse(b.lastActivity).compareTo(DateTime.parse(a.lastActivity))
    );
    print("Loaded ${groups.length} groups"); // Debug print
    return groups;
  }
}