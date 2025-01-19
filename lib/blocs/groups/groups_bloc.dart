import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';
import 'package:grid_frontend/blocs/groups/groups_state.dart';


import '../../models/grid_user.dart';

class GroupsBloc extends Bloc<GroupsEvent, GroupsState> {
  final RoomService roomService;
  final RoomRepository roomRepository;
  final UserRepository userRepository;
  final LocationRepository locationRepository;
  final UserLocationProvider userLocationProvider;
  final MapBloc mapBloc;
  List<Room> _allGroups = [];
  bool _isUpdatingMembers = false;

  GroupsBloc({
    required this.roomService,
    required this.roomRepository,
    required this.userRepository,
    required this.mapBloc,
    required this.locationRepository,
    required this.userLocationProvider,
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
      log("GroupsBloc: Error loading groups", error: e);
      emit(GroupsError(e.toString()));
    }
  }

  Future<void> refreshGroupMembers(String roomId) async {
    try {
      final room = await roomRepository.getRoomById(roomId);
      if (room == null) return;

      // Get all relationships and membership statuses in a single call
      final relationships = await userRepository.getUserRelationshipsForRoom(roomId);
      final memberIds = relationships.map((r) => r['userId'] as String).toSet();

      final members = await userRepository.getGroupParticipants();
      final filteredMembers = members.where(
              (user) => memberIds.contains(user.userId)
      ).toList();

      final membershipStatuses = Map.fromEntries(
          relationships.map((r) => MapEntry(
              r['userId'] as String,
              r['membershipStatus'] as String? ?? 'join'
          ))
      );

      if (state is GroupsLoaded) {
        final currentState = state as GroupsLoaded;
        emit(GroupsLoaded(
          currentState.groups,
          selectedRoomId: roomId,
          selectedRoomMembers: filteredMembers,
          membershipStatuses: membershipStatuses,
        ));
      }
    } catch (e) {
      log("Error refreshing group members", error: e);
    }
  }

  Future<void> _onRefreshGroups(RefreshGroups event, Emitter<GroupsState> emit) async {
    log("GroupsBloc: Handling RefreshGroups event");
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

    } catch (e) {
      log("GroupsBloc: Error in RefreshGroups", error: e);
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
      log("GroupsBloc: Error deleting group", error: e);
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
      log("GroupsBloc: Handling UpdateGroup for room ${event.roomId}");
      final room = await roomRepository.getRoomById(event.roomId);
      if (room != null) {
        final index = _allGroups.indexWhere((g) => g.roomId == event.roomId);
        if (index != -1) {
          _allGroups[index] = room;
          if (state is GroupsLoaded) {
            final currentState = state as GroupsLoaded;

            // Get updated member data if this is the selected room
            if (currentState.selectedRoomId == event.roomId) {
              log("GroupsBloc: Updating members for selected room");
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
                  log("GroupsBloc: Updated status for ${user.userId} to ${status ?? 'join'}");
                }),
              );

              log("GroupsBloc: Emitting new state with ${filteredMembers.length} members");
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
      log("GroupsBloc: Error updating group", error: e);
    }
  }

  Future<void> _onLoadGroupMembers(
      LoadGroupMembers event,
      Emitter<GroupsState> emit,
      ) async {
    if (_isUpdatingMembers) return;
    _isUpdatingMembers = true;

    try {
      final room = await roomRepository.getRoomById(event.roomId);
      if (room == null) {
        throw Exception('Room not found');
      }

      // Get current state to preserve existing statuses
      final currentState = state as GroupsLoaded?;
      final existingStatuses = currentState?.membershipStatuses ?? {};

      // Get all relationships including invited members
      final relationships = await userRepository.getUserRelationshipsForRoom(event.roomId);
      final members = await userRepository.getGroupParticipants();

      // Build status map starting with existing statuses
      final Map<String, String> membershipStatuses = Map.from(existingStatuses);

      // Keep track of all member IDs including invited ones
      final Set<String> allMemberIds = {};

      // Process each relationship and update status
      for (var relationship in relationships) {
        final userId = relationship['userId'] as String;
        allMemberIds.add(userId);  // Add to our tracking set

        // First check Matrix status
        final matrixStatus = await roomService.getUserRoomMembership(
          event.roomId,
          userId,
        );

        if (matrixStatus != null) {
          // Use Matrix status if available
          membershipStatuses[userId] = matrixStatus;
        } else {
          // Fall back to stored status
          membershipStatuses[userId] = relationship['membershipStatus'] as String? ?? 'join';
        }
      }

      // Filter members based on all relationships (including invites)
      var filteredMembers = members.where(
              (user) => allMemberIds.contains(user.userId)
      ).toList();

      // Add any invited users that might not be in the members list yet
      for (var userId in allMemberIds) {
        if (!filteredMembers.any((m) => m.userId == userId)) {
          // Try to get user profile for invited user
          try {
            final profileInfo = await roomService.client.getUserProfile(userId);
            filteredMembers.add(GridUser(
              userId: userId,
              displayName: profileInfo.displayname ?? userId,
              avatarUrl: profileInfo.avatarUrl?.toString(),
              lastSeen: DateTime.now().toIso8601String(),
              profileStatus: "",
            ));
          } catch (e) {
            log('Error fetching profile for invited user $userId', error: e);
            // Add basic user info if profile fetch fails
            filteredMembers.add(GridUser(
              userId: userId,
              displayName: userId,
              lastSeen: DateTime.now().toIso8601String(),
              profileStatus: "",
            ));
          }
        }
      }

      // Handle deleted users
      filteredMembers = filteredMembers.map((u) =>
      (u.displayName?.isEmpty ?? true)
          ? GridUser(
        userId: u.userId,
        displayName: 'Deleted User',
        avatarUrl: u.avatarUrl,
        lastSeen: u.lastSeen,
        profileStatus: u.profileStatus,
      )
          : u
      ).toList();

      emit(GroupsLoaded(
        currentState?.groups ?? [],
        selectedRoomId: event.roomId,
        selectedRoomMembers: filteredMembers,
        membershipStatuses: membershipStatuses,
      ));

    } catch (e) {
      log("Error loading group members", error: e);
    } finally {
      _isUpdatingMembers = false;
    }
  }
  // In GroupsBloc class
  Future<void> handleNewMemberInvited(String roomId, String userId) async {
    if (_isUpdatingMembers) return;
    _isUpdatingMembers = true;

    try {
      // First wait for Matrix sync to ensure we have latest state
      await roomService.client.sync();

      // Verify invite status from Matrix
      final inviteStatus = await roomService.getUserRoomMembership(roomId, userId);
      if (inviteStatus != 'invite') {
        // Wait briefly and check again in case of sync delay
        await Future.delayed(const Duration(milliseconds: 500));
        await roomService.client.sync();
      }

      // Get user profile and update/insert user
      final profileInfo = await roomService.client.getUserProfile(userId);
      final newUser = GridUser(
        userId: userId,
        displayName: profileInfo.displayname,
        avatarUrl: profileInfo.avatarUrl?.toString(),
        lastSeen: DateTime.now().toIso8601String(),
        profileStatus: "",
      );
      await userRepository.insertUser(newUser);

      // Update relationship with invite status
      await userRepository.insertUserRelationship(
          userId,
          roomId,
          false,
          membershipStatus: 'invite'
      );

      // Force a full member list refresh
      add(LoadGroupMembers(roomId));
    } catch (e) {
      log("Error handling new member invite", error: e);
    } finally {
      _isUpdatingMembers = false;
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
      log("GroupsBloc: Error updating member status", error: e);
    }
  }

  Future<void> handleMemberKicked(String roomId, String userId) async {
    try {
      final currentState = state as GroupsLoaded?;
      if (currentState == null) return;

      // Create a copy of groups and update the specific room
      final updatedGroups = List<Room>.from(currentState.groups);
      final roomIndex = updatedGroups.indexWhere((r) => r.roomId == roomId);
      if (roomIndex != -1) {
        final room = updatedGroups[roomIndex];
        final updatedMembers = room.members.where((id) => id != userId).toList();
        updatedGroups[roomIndex] = room.copyWith(
            members: updatedMembers,
            lastActivity: DateTime.now().toIso8601String()
        );
      }

      // Update status map
      final updatedStatuses = Map<String, String>.from(currentState.membershipStatuses ?? {});
      updatedStatuses[userId] = 'leave';

      // Emit immediate update for kicked user
      emit(GroupsLoaded(
        updatedGroups,
        selectedRoomId: currentState.selectedRoomId,
        selectedRoomMembers: currentState.selectedRoomMembers?.where((m) => m.userId != userId).toList(),
        membershipStatuses: updatedStatuses,
      ));

      // Now perform actual cleanup
      await Future.wait([
        userRepository.removeUserRelationship(userId, roomId),
        userRepository.updateMembershipStatus(userId, roomId, 'leave'),
        roomRepository.removeRoomParticipant(roomId, userId)
      ]);

      final room = await roomRepository.getRoomById(roomId);
      if (room != null) {
        // Update room with new member list
        final updatedMembers = room.members.where((id) => id != userId).toList();
        final updatedRoom = room.copyWith(
            members: updatedMembers,
            lastActivity: DateTime.now().toIso8601String()
        );
        await roomRepository.updateRoom(updatedRoom);
      }

      // Check if user should be cleaned up
      final userRooms = await roomRepository.getUserRooms(userId);
      final directRoom = await userRepository.getDirectRoomForContact(userId);
      if (userRooms.isEmpty && directRoom == null) {
        final wasDeleted = await locationRepository.deleteUserLocationsIfNotInRooms(userId);
        if (wasDeleted) {
          userLocationProvider.removeUserLocation(userId);
          mapBloc.add(RemoveUserLocation(userId));
        }
        await userRepository.deleteUser(userId);
      }

      // Final refresh to ensure everything is in sync
      add(LoadGroupMembers(roomId));
    } catch (e) {
      log("Error handling kicked member", error: e);
    }
  }

  Future<List<Room>> _loadGroups() async {
    final groups = await roomRepository.getNonExpiredRooms();
    groups.sort((a, b) =>
        DateTime.parse(b.lastActivity).compareTo(DateTime.parse(a.lastActivity))
    );
    log("Loaded ${groups.length} groups"); // Debug print
    return groups;
  }
}