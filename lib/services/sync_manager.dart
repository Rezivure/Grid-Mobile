import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/services/message_processor.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/models/room.dart' as GridRoom;
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/models/grid_user.dart' as GridUser;


import '../blocs/groups/groups_bloc.dart';
import '../blocs/groups/groups_event.dart';

import '../blocs/contacts/contacts_bloc.dart';
import '../blocs/contacts/contacts_event.dart';

import '../blocs/map/map_bloc.dart';
import '../blocs/map/map_event.dart';

import '../models/pending_message.dart';

class SyncManager with ChangeNotifier {
  final Client client;
  final RoomService roomService;
  final MessageProcessor messageProcessor;
  final RoomRepository roomRepository;
  final UserRepository userRepository;
  final LocationRepository locationRepository;
  final MapBloc mapBloc;
  final ContactsBloc contactsBloc;
  final GroupsBloc groupsBloc;
  final List<PendingMessage> _pendingMessages = [];
  bool _isActive = true;

  bool _isSyncing = false;
  final List<Map<String, dynamic>> _invites = [];
  final Map<String, List<Map<String, dynamic>>> _roomMessages = {};
  bool _isInitialized = false;

  SyncManager(
      this.client,
      this.messageProcessor,
      this.roomRepository,
      this.userRepository,
      this.roomService,
      this.mapBloc,
      this.contactsBloc,
      this.locationRepository,
      this.groupsBloc
      );

  List<Map<String, dynamic>> get invites => List.unmodifiable(_invites);
  Map<String, List<Map<String, dynamic>>> get roomMessages => Map.unmodifiable(_roomMessages);
  int get totalInvites => _invites.length;

  Future<void> initialize() async {
    if (_isInitialized) return; // Prevent re-initialization
    _isInitialized = true;

    print("Initializing Sync Manager...");
    await roomService.cleanRooms();
    await fetchInitialData();
    await startSync();
  }

  Future<void> startSync() async {
    if (_isSyncing) return;

    _isSyncing = true;
    client.sync();


    client.onSync.stream.listen((SyncUpdate syncUpdate) {
      // Process invites
      syncUpdate.rooms?.invite?.forEach((roomId, inviteUpdate) {
        _processInvite(roomId, inviteUpdate);
      });

      // Process room messages and joins
      syncUpdate.rooms?.join?.forEach((roomId, joinedRoomUpdate) {
        print("Got join update for room: $roomId");
        _processRoomMessages(roomId, joinedRoomUpdate);

        // Check if there are any state events before processing
        if ((joinedRoomUpdate.state ?? []).isNotEmpty) {
          print("Found state events, processing join");
          _processRoomJoin(roomId, joinedRoomUpdate);
        }
      });

      // Process room departures and kicks
      syncUpdate.rooms?.leave?.forEach((roomId, leftRoomUpdate) {
        _processRoomLeaveOrKick(roomId, leftRoomUpdate);
      });
    });
  }

  void handleAppLifecycleState(bool isActive) {
    _isActive = isActive;
    if (isActive && _pendingMessages.isNotEmpty) {
      _processPendingMessages();
    }
  }

  Future<void> stopSync() async {
    if (!_isSyncing) return;

    _isSyncing = false;
    client.abortSync();
  }

  void _processInvite(String roomId, InvitedRoomUpdate inviteUpdate) {
    if (!_inviteExists(roomId)) {
      final inviter = _extractInviter(inviteUpdate);
      final roomName = _extractRoomName(inviteUpdate) ?? 'Unnamed Room';

      final inviteData = {
        'roomId': roomId,
        'inviter': inviter,
        'roomName': roomName,
        'inviteState': inviteUpdate.inviteState,
      };

      _invites.add(inviteData);
      notifyListeners();
    }
  }

  Future<void> _processRoomLeave(String roomId, LeftRoomUpdate leftRoomUpdate) async {
    try {
      final room = await roomRepository.getRoomById(roomId);

      if (room != null && !room.isGroup) {
        final participants = await roomRepository.getRoomParticipants(roomId);
        final otherUserId = participants.firstWhere(
              (id) => id != client.userID,
          orElse: () => '',
        );

        if (otherUserId.isNotEmpty) {
          print("Processing complete removal for user: $otherUserId");

          // Check if user exists in any other rooms
          final userRooms = await roomRepository.getUserRooms(otherUserId);

          // Clean up database
          await userRepository.removeContact(otherUserId);
          await roomRepository.deleteRoom(roomId);

          // If user isn't in any other rooms, clean up all their data
          if (userRooms.length <= 1) {  // <= 1 because current room is still counted
            print("User not in any other rooms, removing completely");
            await locationRepository.deleteUserLocations(otherUserId);
            await userRepository.deleteUser(otherUserId);
          }

          // Update UI
          mapBloc.add(RemoveUserLocation(otherUserId));
          contactsBloc.add(RefreshContacts());

          print('Completed cleanup for user $otherUserId');
        }
      }
    } catch (e) {
      print('Error processing room leave: $e');
    }
  }

  Future<void> _handleKickedFromRoom(GridRoom.Room room) async {
    try {
      final roomId = room.roomId;
      final participants = room.members;

      // First, remove any UserRelationships for this room
      for (final participantId in participants) {
        await userRepository.removeUserRelationship(participantId, roomId);
      }

      // Remove all RoomParticipants
      await roomRepository.removeAllParticipants(roomId);

      // Delete the room itself
      await roomRepository.deleteRoom(roomId);

      // For each participant, check if they need complete cleanup
      for (final participantId in participants) {
        final userRooms = await roomRepository.getUserRooms(participantId);
        final hasDirectRoom = await userRepository.getDirectRoomForContact(participantId);

        if (userRooms.isEmpty && hasDirectRoom == null) {
          print("Cleaning up user completely: $participantId");
          await locationRepository.deleteUserLocations(participantId);
          await userRepository.deleteUser(participantId);
          mapBloc.add(RemoveUserLocation(participantId));
        }
      }

      // Update UI with staggered refreshes to ensure everything updates
      groupsBloc.add(RefreshGroups());
      groupsBloc.add(LoadGroups());
      mapBloc.add(MapLoadUserLocations());

      // Force additional updates after a delay
      Future.delayed(const Duration(milliseconds: 500), () {
        groupsBloc.add(RefreshGroups());
        groupsBloc.add(LoadGroups());
      });

      Future.delayed(const Duration(seconds: 1), () {
        groupsBloc.add(RefreshGroups());
        groupsBloc.add(LoadGroups());
        mapBloc.add(MapLoadUserLocations());
      });

      print("Completed kick cleanup for room: $roomId");
    } catch (e) {
      print('Error handling kicked from room: $e');
    }
  }

  Future<void> _processRoomLeaveOrKick(String roomId, LeftRoomUpdate leftRoomUpdate) async {
    try {
      // First check if this was a kick by examining state events
      bool wasKicked = false;
      String? kickedBy;

      for (var event in (leftRoomUpdate.timeline?.events ?? [])) {
        if (event.type == 'm.room.member' &&
            event.stateKey == client.userID &&
            event.content['membership'] == 'leave' &&
            event.senderId != client.userID) {
          wasKicked = true;
          kickedBy = event.senderId;
          break;
        }
      }

      final room = await roomRepository.getRoomById(roomId);
      if (room == null) return;

      if (wasKicked) {
        print("User was kicked from room $roomId by $kickedBy");

        // Immediately clear from local storage
        await roomRepository.deleteRoom(roomId);
        await roomRepository.removeAllParticipants(roomId);

        // Then do full cleanup
        await _handleKickedFromRoom(room);

        // Force UI refresh
        groupsBloc.add(RefreshGroups());
        groupsBloc.add(LoadGroups());
      } else {
        // Handle normal leave/departure
        await _processRoomLeave(roomId, leftRoomUpdate);
      }
    } catch (e) {
      print('Error processing room leave/kick: $e');

      // Even if we get an error, try to clean up local data
      try {
        await roomRepository.deleteRoom(roomId);
        await roomRepository.removeAllParticipants(roomId);
        groupsBloc.add(RefreshGroups());
        groupsBloc.add(LoadGroups());
      } catch (cleanupError) {
        print('Error during emergency cleanup: $cleanupError');
      }
    }
  }

  void _processRoomMessages(String roomId, JoinedRoomUpdate joinedRoomUpdate) {
    final timelineEvents = joinedRoomUpdate.timeline?.events ?? [];
    for (var event in timelineEvents) {
      if (!_isActive) {
        // Queue message if app is in background
        _pendingMessages.add(PendingMessage(
          roomId: roomId,
          eventId: event.eventId ?? '',
          event: event,
        ));
        continue;
      }

      messageProcessor.processEvent(roomId, event).then((message) {
        if (message != null) {
          _roomMessages.putIfAbsent(roomId, () => []).add(message);
          notifyListeners();
        }
      }).catchError((e) {
        if (e is PlatformException && e.code == '-25308') {
          // Queue message if we get keychain access error
          _pendingMessages.add(PendingMessage(
            roomId: roomId,
            eventId: event.eventId ?? '',
            event: event,
          ));
        } else {
          print("Error processing event ${event.eventId}: $e");
        }
      });
    }
  }

  Future<void> _processPendingMessages() async {
    if (_pendingMessages.isEmpty) return;

    print("Processing ${_pendingMessages.length} pending messages");

    final messagesToProcess = List<PendingMessage>.from(_pendingMessages);
    _pendingMessages.clear();

    for (var pendingMessage in messagesToProcess) {
      await messageProcessor.processEvent(
        pendingMessage.roomId,
        pendingMessage.event,
      ).then((message) {
        if (message != null) {
          _roomMessages.putIfAbsent(pendingMessage.roomId, () => []).add(message);
          notifyListeners();
        }
      }).catchError((e) {
        print("Error processing pending event ${pendingMessage.eventId}: $e");
      });
    }
  }

  Future<void> handleNewGroupCreation(String roomId) async {
    print("SyncManager: Handling new group creation for room $roomId");

    final matrixRoom = client.getRoomById(roomId);
    if (matrixRoom != null) {
      // Process the room immediately
      await initialProcessRoom(matrixRoom);

      // Force multiple group refreshes
      groupsBloc.add(RefreshGroups());

      // Add staggered refreshes
      Future.delayed(const Duration(milliseconds: 500), () {
        groupsBloc.add(LoadGroups());
      });

      Future.delayed(const Duration(milliseconds: 1000), () {
        groupsBloc.add(RefreshGroups());
        groupsBloc.add(LoadGroups());
      });
    }
  }

  Future<void> _processRoomJoin(String roomId, JoinedRoomUpdate joinedRoomUpdate) async {
    try {
      print("Processing room join for room: $roomId");
      final stateEvents = joinedRoomUpdate.state ?? [];
      print("Found ${stateEvents.length} state events");

      // First pass: Check if this is an initial room join
      bool isInitialJoin = false;
      bool isGroupRoom = false;

      for (var event in stateEvents) {
        if (event.type == 'm.room.member' &&
            event.stateKey == client.userID &&
            event.content['membership'] == 'join' &&
            event.prevContent?['membership'] != 'join') {
          isInitialJoin = true;
          break;
        }
      }

      // If it's an initial join, process the full room
      if (isInitialJoin) {
        print("Processing initial room join");
        final matrixRoom = client.getRoomById(roomId);
        if (matrixRoom != null) {
          final room = await roomRepository.getRoomById(roomId);
          isGroupRoom = room?.isGroup ?? false;

          await initialProcessRoom(matrixRoom);

          // Update appropriate bloc based on room type
          if (isGroupRoom) {
            groupsBloc.add(RefreshGroups());
          } else {
            contactsBloc.add(RefreshContacts());
          }

          mapBloc.add(MapLoadUserLocations());
        }
        return;
      }

      // Second pass: Process individual state events
      for (var event in stateEvents) {
        print("Processing event type: ${event.type}");
        if (event.type == 'm.room.member') {
          await _processMemberStateEvent(roomId, event);
        } else {
          // Process other state events through message processor
          await messageProcessor.processEvent(roomId, event).then((message) {
            if (message != null) {
              _roomMessages.putIfAbsent(roomId, () => []).add(message);
              notifyListeners();
            }
          });
        }
      }
    } catch (e) {
      print('Error processing room join: $e');
    }
  }

  Future<void> _processMemberStateEvent(String roomId, MatrixEvent event) async {
    print("Processing member event: ${event.stateKey} with content: ${event.content}");

    final room = await roomRepository.getRoomById(roomId);
    if (room == null) return;

    if (room.isGroup) {
      final membershipStatus = event.content['membership'] as String? ?? 'invited';

      if (event.stateKey != null) {
        // Update membership status for group rooms
        await userRepository.updateMembershipStatus(
            event.stateKey!,
            roomId,
            membershipStatus
        );

        // Since it's a group room, update the GroupsBloc
        groupsBloc.add(UpdateGroup(roomId));

        // If this is a newly invited member, make sure their profile is in the database
        if (membershipStatus == 'invite') {
          try {
            final profileInfo = await client.getUserProfile(event.stateKey!);
            final gridUser = GridUser.GridUser(
              userId: event.stateKey!,
              displayName: profileInfo.displayname,
              avatarUrl: profileInfo.avatarUrl?.toString(),
              lastSeen: DateTime.now().toIso8601String(),
              profileStatus: "",
            );
            await userRepository.insertUser(gridUser);
          } catch (e) {
            print('Error fetching profile for invited user ${event.stateKey}: $e');
          }
        }
      }
    }

    if (event.content['membership'] == 'leave') {
      await _handleMemberLeave(roomId, event.stateKey);
    } else if (event.content['membership'] == 'join') {
      // Handle updates to existing members (profile changes etc)
      if (event.stateKey != null) {
        try {
          final profileInfo = await client.getUserProfile(event.stateKey!);
          final gridUser = GridUser.GridUser(
            userId: event.stateKey!,
            displayName: profileInfo.displayname,
            avatarUrl: profileInfo.avatarUrl?.toString(),
            lastSeen: DateTime.now().toIso8601String(),
            profileStatus: "",
          );
          await userRepository.insertUser(gridUser);

          if (room.isGroup) {
            groupsBloc.add(UpdateGroup(roomId));
          }
        } catch (e) {
          print('Error updating user profile for ${event.stateKey}: $e');
        }
      }
    }
  }

  Future<void> _handleMemberLeave(String roomId, String? userId) async {
    if (userId == null || userId == client.userID) return;

    print("Processing leave for user: $userId in room: $roomId");
    final room = await roomRepository.getRoomById(roomId);

    if (room != null) {
      if (room.isGroup) {
        try {
          // Remove the user from room members list
          final updatedMembers = room.members.where((id) => id != userId).toList();
          final updatedRoom = GridRoom.Room(
            roomId: room.roomId,
            name: room.name,
            isGroup: room.isGroup,
            lastActivity: DateTime.now().toIso8601String(),
            avatarUrl: room.avatarUrl,
            members: updatedMembers,
            expirationTimestamp: room.expirationTimestamp,
          );

          // Update the room with new member list
          await roomRepository.updateRoom(updatedRoom);

          // Remove all relationships for this user in this room
          await userRepository.removeUserRelationship(userId, roomId);
          await roomRepository.removeRoomParticipant(roomId, userId);

          // Update membership status to 'leave'
          await userRepository.updateMembershipStatus(userId, roomId, 'leave');

          // Check if user should be completely cleaned up
          final userRooms = await roomRepository.getUserRooms(userId);
          final hasDirectRoom = await userRepository.getDirectRoomForContact(userId);

          if (userRooms.isEmpty && hasDirectRoom == null) {
            print("User not in any other rooms/contacts, cleaning up completely");
            await locationRepository.deleteUserLocations(userId);
            await userRepository.deleteUser(userId);
            mapBloc.add(RemoveUserLocation(userId));
          }

          // Update UI with staggered refreshes
          groupsBloc.add(LoadGroupMembers(roomId));
          groupsBloc.add(UpdateGroup(roomId));
          groupsBloc.add(RefreshGroups());

          // Additional delayed updates to ensure sync
          Future.delayed(const Duration(milliseconds: 500), () {
            groupsBloc.add(LoadGroups());
            groupsBloc.add(LoadGroupMembers(roomId));
          });

        } catch (e) {
          print('Error processing group member leave: $e');
        }
      } else {
        // Handle direct room cleanup
        await userRepository.removeContact(userId);
        await roomRepository.deleteRoom(roomId);

        final userRooms = await roomRepository.getUserRooms(userId);
        if (userRooms.isEmpty) {
          await locationRepository.deleteUserLocations(userId);
          await userRepository.deleteUser(userId);
          mapBloc.add(RemoveUserLocation(userId));
        }

        contactsBloc.add(RefreshContacts());
      }
    }
  }
  Future<void> fetchInitialData() async {
    try {
      final response = await client.sync(fullState: true);

      // Update Invites
      response.rooms?.invite?.forEach((roomId, inviteUpdate) {
        _processInvite(roomId, inviteUpdate);
      });

      // Fetch and Cache Rooms
      for (var room in client.rooms) {
        initialProcessRoom(room);
      }

      // Refresh contacts after sync
      contactsBloc.add(LoadContacts());

      notifyListeners();
    } catch (e) {
      print("Error fetching initial data: $e");
    }
  }


  Future<void> initialProcessRoom(Room room) async {
    // Check if the room already exists
    final existingRoom = await roomRepository.getRoomById(room.id);

    final isDirect = isDirectRoom(room.name ?? '');
    final customRoom = GridRoom.Room(
      roomId: room.id,
      name: room.name ?? 'Unnamed Room',
      isGroup: !isDirect,
      lastActivity: DateTime.now().toIso8601String(),
      avatarUrl: room.avatar?.toString(),
      members: room.getParticipants().map((p) => p.id).toList(),
      expirationTimestamp: extractExpirationTimestamp(room.name ?? ''),
    );

    if (existingRoom == null) {
      // Insert new room
      await roomRepository.insertRoom(customRoom);
      print('Inserted new room: ${room.id}');
    } else {
      // Update existing room
      await roomRepository.updateRoom(customRoom);
      print('Updated existing room: ${room.id}');
    }

    // Sync participants
    final currentParticipants = customRoom.members;
    final existingParticipants = await roomRepository.getRoomParticipants(room.id);

    for (var participantId in currentParticipants) {
      try {
        // Fetch participant details using client.getUserProfile
        final profileInfo = await client.getUserProfile(participantId);

        // Create or update the user in the database
        final gridUser = GridUser.GridUser(
          userId: participantId,
          displayName: profileInfo.displayname,
          avatarUrl: profileInfo.avatarUrl?.toString(),
          lastSeen: DateTime.now().toIso8601String(),
          profileStatus: "", // Future implementations
        );

        await userRepository.insertUser(gridUser);

        String? membershipStatus;
        if (!isDirect) {
          membershipStatus = await roomService.getUserRoomMembership(room.id, participantId) ?? 'invited';
        }

        await userRepository.insertUserRelationship(
            participantId,
            room.id,
            isDirect,
            membershipStatus: !isDirect ? membershipStatus : null
        );

        final customRoom = await roomRepository.getRoomById(room.id);
        if (customRoom?.isGroup ?? false) {
          print('Updating group in bloc: ${room.id}');
          groupsBloc.add(UpdateGroup(room.id));
        }
        print('Processed user ${participantId} in room ${room.id}');
      } catch (e) {
        print('Error fetching profile for user $participantId: $e');
      }
    }

    // Remove participants who are no longer in the room
    for (var participant in existingParticipants) {
      if (!currentParticipants.contains(participant)) {
        await roomRepository.removeRoomParticipant(room.id, participant);
        print('Removed participant $participant from room ${room.id}');
      }
    }
  }

  Future<void> acceptInviteAndSync(String roomId) async {
    try {
      // Join the room
      final didJoin = await roomService.acceptInvitation(roomId);

      if (didJoin) {
        print('Successfully joined room $roomId');

        // Process the room to ensure database updates
        await roomService.updateSingleRoom(roomId);
        final room = client.getRoomById(roomId);
        if (room != null) {
          await initialProcessRoom(room);
        }

        // Trigger a full client sync to fetch all updates
        await client.sync(timeout: 10000);
        print('Sync completed for room $roomId');
      } else {
        throw Exception('Failed to join room');
      }
      // Remove invite since excepted
      removeInvite(roomId);
    } catch (e) {
      print('Error during room join and sync: $e');
      throw e; // Re-throw for error handling in calling code
    }
  }



  String _extractInviter(InvitedRoomUpdate inviteUpdate) {
    final inviteState = inviteUpdate.inviteState;
    if (inviteState != null) {
      for (var event in inviteState) {
        if (event.type == 'm.room.member' &&
            event.stateKey == client.userID &&
            event.content['membership'] == 'invite') {
          return event.senderId ?? 'Unknown';
        }
      }
    }
    return 'Unknown';
  }

  String? _extractRoomName(InvitedRoomUpdate inviteUpdate) {
    final inviteState = inviteUpdate.inviteState;
    if (inviteState != null) {
      for (var event in inviteState) {
        if (event.type == 'm.room.name') {
          return event.content['name'] as String?;
        }
      }
    }
    return null;
  }

  bool _inviteExists(String roomId) {
    return _invites.any((invite) => invite['roomId'] == roomId);
  }

  void clearInvites() {
    _invites.clear();
    notifyListeners();
  }

  void clearRoomMessages(String roomId) {
    _roomMessages.remove(roomId);
    notifyListeners();
  }

  void removeInvite(String roomId) {
    _invites.removeWhere((invite) => invite['roomId'] == roomId);
    notifyListeners();
  }

  void clearAllRoomMessages() {
    _roomMessages.clear();
    notifyListeners();
  }

  bool _messageExists(String roomId, String? eventId) {
    final roomMessages = _roomMessages[roomId] ?? [];
    return roomMessages.any((message) => message['eventId'] == eventId);
  }
}
