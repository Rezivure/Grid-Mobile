import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/services/message_processor.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/models/room.dart' as GridRoom;
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/models/grid_user.dart' as GridUser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/services/logger_service.dart';

import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/services/profile_announcement_service.dart';
import 'package:grid_frontend/services/profile_picture_service.dart';


import '../blocs/groups/groups_bloc.dart';
import '../blocs/groups/groups_event.dart';

import '../blocs/contacts/contacts_bloc.dart';
import '../blocs/contacts/contacts_event.dart';

import '../blocs/map/map_bloc.dart';
import '../blocs/map/map_event.dart';

import '../models/pending_message.dart';
import '../models/sharing_preferences.dart';



class SyncManager with ChangeNotifier {
  static const String _tag = 'SyncManager';
  
  final Client client;
  final RoomService roomService;
  final MessageProcessor messageProcessor;
  final RoomRepository roomRepository;
  final UserRepository userRepository;
  final LocationRepository locationRepository;
  final SharingPreferencesRepository sharingPreferencesRepository;
  final UserLocationProvider userLocationProvider;
  final MapBloc mapBloc;
  final ContactsBloc contactsBloc;
  final GroupsBloc groupsBloc;
  final List<PendingMessage> _pendingMessages = [];
  bool _isActive = true;

  bool _isSyncing = false;
  final List<Map<String, dynamic>> _invites = [];
  final Map<String, List<Map<String, dynamic>>> _roomMessages = {};
  bool _isInitialized = false;
  String? _sinceToken;
  
  late ProfileAnnouncementService _profileAnnouncementService;


  SyncManager(
      this.client,
      this.messageProcessor,
      this.roomRepository,
      this.userRepository,
      this.roomService,
      this.mapBloc,
      this.contactsBloc,
      this.locationRepository,
      this.groupsBloc,
      this.userLocationProvider,
      this.sharingPreferencesRepository,
      ) {
    _profileAnnouncementService = ProfileAnnouncementService(
      client: client,
      profilePictureService: ProfilePictureService(),
    );
  }

  List<Map<String, dynamic>> get invites => List.unmodifiable(_invites);
  Map<String, List<Map<String, dynamic>>> get roomMessages => Map.unmodifiable(_roomMessages);
  int get totalInvites => _invites.length;

  Future<void> _loadSinceToken() async {
    final prefs = await SharedPreferences.getInstance();
    _sinceToken = prefs.getString('syncSinceToken');
    Logger.debug(_tag, 'Loaded since token', data: {'hasToken': _sinceToken != null});
  }

  Future<void> _saveSinceToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('syncSinceToken', token);
    Logger.debug(_tag, 'Saved since token');
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    Logger.info(_tag, 'Initializing sync manager');
    try {
      await _loadSinceToken();
      await roomService.cleanRooms();

      // Perform reconciliation check on app load
      await _reconcileLocalStateWithServer();

      final response = await client.sync(
        since: _sinceToken,
        fullState: _sinceToken == null,
        timeout: 15000,
      );

      if (response.nextBatch != null) {
        await _saveSinceToken(response.nextBatch!);
        _sinceToken = response.nextBatch;
      }


      roomService.getAndUpdateDisplayName();
      _processInitialSync(response);
      await startSync();
      _isInitialized = true; // Only set after successful completion
      Logger.info(_tag, 'Sync manager initialized successfully');
    } catch (e) {
      Logger.error(_tag, 'Failed to initialize sync manager', error: e);
      // Maybe add some retry logic here
    }
  }



  Future<void> startSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    client.sync(
      fullState: false,
      timeout: 10000,
    );



    client.onSync.stream.listen((SyncUpdate syncUpdate) {
      // Process invites
      syncUpdate.rooms?.invite?.forEach((roomId, inviteUpdate) {
        _processInvite(roomId, inviteUpdate);
      });

      // Process room messages and joins
      syncUpdate.rooms?.join?.forEach((roomId, joinedRoomUpdate) {
        // Only log if there are actual updates
        if ((joinedRoomUpdate.state ?? []).isNotEmpty || 
            (joinedRoomUpdate.timeline?.events ?? []).isNotEmpty) {
          Logger.debug(_tag, 'Room update', data: {'roomId': roomId});
        }
        
        _processRoomMessages(roomId, joinedRoomUpdate);

        // Check if there are any state events before processing
        if ((joinedRoomUpdate.state ?? []).isNotEmpty) {
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
    if (isActive) {
      if (_pendingMessages.isNotEmpty) {
        _processPendingMessages();
      }
      // full refresh as well
      client.sync(fullState: true, timeout: 10000).then((_) {
        mapBloc.add(MapLoadUserLocations()); // Refresh locations
      }).catchError((e) {
        print('Error during resume sync: $e');
      });
      
      // Check if we should announce profile based on 6-day interval
      if (!utils.isCustomHomeserver(client.homeserver.toString())) {
        _profileAnnouncementService.shouldAnnounceBasedOnTime().then((shouldAnnounce) {
          if (shouldAnnounce) {
            _profileAnnouncementService.announceToAllActiveRooms();
          }
        });
      }
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

  Future<void> clearAllState() async {
    _invites.clear();
    _roomMessages.clear();
    _pendingMessages.clear();
    _isInitialized = false;
    _isSyncing = false;

    // Stop syncing
    await stopSync();
    // Notify listeners of the changes
    notifyListeners();
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
          userLocationProvider.removeUserLocation(participantId);
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

    try {
      final matrixRoom = client.getRoomById(roomId);
      if (matrixRoom != null) {
        // First sync to ensure we have latest state
        await client.sync(timeout: 10000);

        // Process the room and wait for completion
        await initialProcessRoom(matrixRoom);

        // Verify room was processed
        final processedRoom = await roomRepository.getRoomById(roomId);
        print("Room processed status: ${processedRoom != null}");

        // Force immediate refresh
        groupsBloc.add(RefreshGroups());

        // Staggered refreshes with verification
        Future.delayed(const Duration(milliseconds: 500), () async {
          final room = await roomRepository.getRoomById(roomId);
          if (room != null) {
            groupsBloc.add(LoadGroups());
            groupsBloc.add(RefreshGroups());
          }
        });

        Future.delayed(const Duration(seconds: 1), () async {
          final room = await roomRepository.getRoomById(roomId);
          if (room != null) {
            groupsBloc.add(LoadGroups());
            groupsBloc.add(RefreshGroups());
          }
        });
      }
    } catch (e) {
      print("Error in handleNewGroupCreation: $e");
    }
  }

  Future<void> _processRoomJoin(String roomId, JoinedRoomUpdate joinedRoomUpdate) async {
    try {
      final stateEvents = joinedRoomUpdate.state ?? [];
      Logger.debug(_tag, 'Processing room join', data: {
        'roomId': roomId,
        'stateEvents': stateEvents.length
      });

      // First pass: Check if this is an initial room join
      bool isInitialJoin = false;
      bool isGroupRoom = false;

      final room = await roomRepository.getRoomById(roomId);
      isInitialJoin = room == null;  // Keep this for immediate contact inserts

      // Also check for actual join events (e.g., accepting invite)
      for (var event in stateEvents) {
        if (event.type == 'm.room.member') {
          final membershipStatus = event.content['membership'] as String?;
          final prevMembership = event.prevContent?['membership'] as String?;

          // Consider it a join if:
          // 1. New member joining (membership = join, prev != join)
          // 2. NOT someone being kicked (prev = join, membership = leave)
          if (membershipStatus == 'join' &&
              prevMembership != 'join' &&
              !(prevMembership == 'join' && membershipStatus == 'leave')) {
            isInitialJoin = true;
            break;
          }
        }
      }

      // If it's an initial join, process the full room
      if (isInitialJoin) {
        Logger.info(_tag, 'Initial room join detected', data: {'roomId': roomId});
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
          
          // Announce profile picture to the newly joined room
          if (!utils.isCustomHomeserver(client.homeserver.toString())) {
            await _profileAnnouncementService.announceToRoom(roomId);
          }
        }
        return;
      }

      // Second pass: Process individual state events
      bool needsGroupUpdate = false;
      for (var event in stateEvents) {
        Logger.debug(_tag, 'Processing event type', data: {'type': event.type});
        if (event.type == 'm.room.member') {
          // Don't process member events for kicked users
          final membershipStatus = event.content['membership'] as String?;
          final prevMembership = event.prevContent?['membership'] as String?;

          if (!(prevMembership == 'join' && membershipStatus == 'leave')) {
            await _processMemberStateEvent(roomId, event, shouldUpdateGroup: false);
            needsGroupUpdate = true; // Mark that we need to update group after loop
          }
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
      
      // Update group bloc once after processing all member events
      if (needsGroupUpdate) {
        final room = await roomRepository.getRoomById(roomId);
        if (room?.isGroup == true) {
          Logger.debug(_tag, 'Updating group after member changes', data: {'roomId': roomId});
          groupsBloc.add(UpdateGroup(roomId));
        }
      }
    } catch (e) {
      Logger.error(_tag, 'Error processing room join: $e');
    }
  }

  Future<void> _processMemberStateEvent(String roomId, MatrixEvent event, {bool shouldUpdateGroup = true}) async {
    Logger.debug(_tag, 'Processing member event', data: {
      'stateKey': event.stateKey,
      'membership': event.content['membership']
    });

    final room = await roomRepository.getRoomById(roomId);
    if (room == null) return;

    if (room.isGroup) {
      final membershipStatus = event.content['membership'] as String? ?? 'invited';

      if (event.stateKey != null) {
        await userRepository.updateMembershipStatus(
            event.stateKey!,
            roomId,
            membershipStatus
        );

        if (shouldUpdateGroup) {
          groupsBloc.add(UpdateGroup(roomId));
        }

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
    } else {
      // Handle direct room membership changes
      final membershipStatus = event.content['membership'] as String?;
      
      if (event.stateKey != null && membershipStatus == 'invite') {
        print("SyncManager: Processing invite in direct room for ${event.stateKey}");
        
        try {
          // Fetch user profile and insert/update user
          final profileInfo = await client.getUserProfile(event.stateKey!);
          final gridUser = GridUser.GridUser(
            userId: event.stateKey!,
            displayName: profileInfo.displayname,
            avatarUrl: profileInfo.avatarUrl?.toString(),
            lastSeen: DateTime.now().toIso8601String(),
            profileStatus: "",
          );
          await userRepository.insertUser(gridUser);
          
          // Insert direct relationship
          await userRepository.insertUserRelationship(
            event.stateKey!,
            roomId,
            true, // isDirect
          );
          
          print("SyncManager: Direct contact invite processed, refreshing contacts");
          contactsBloc.add(RefreshContacts());
          
        } catch (e) {
          print('Error processing direct room invite for ${event.stateKey}: $e');
        }
      }
    }

    if (event.stateKey != null) {
      final membershipStatus = event.content['membership'] as String?;

      if (membershipStatus == 'join') {
        try {
          // Update or create user profile
          final profileInfo = await client.getUserProfile(event.stateKey!);
          final gridUser = GridUser.GridUser(
            userId: event.stateKey!,
            displayName: profileInfo.displayname,
            avatarUrl: profileInfo.avatarUrl?.toString(),
            lastSeen: DateTime.now().toIso8601String(),
            profileStatus: "",
          );
          await userRepository.insertUser(gridUser);

          // Update relationship
          await userRepository.insertUserRelationship(
            event.stateKey!,
            roomId,
            !room.isGroup, // isDirect
          );

          // UI updates are handled after processing all events
          if (!room.isGroup) {
            Logger.debug(_tag, 'Direct room join detected, refreshing contacts');
            contactsBloc.add(RefreshContacts());
          }
          
          // Share location when someone else joins a room we're in
          if (event.stateKey != client.userID) {
            Logger.info(_tag, 'Member joined room, sharing location', data: {
              'userId': event.stateKey,
              'roomId': roomId
            });
            await roomService.shareCurrentLocationToRoom(roomId);
          }
        } catch (e) {
          Logger.error(_tag, 'Error updating user profile: $e', data: {'userId': event.stateKey});
        }
      } else if (membershipStatus == 'leave') {
        await _handleMemberLeave(roomId, event.stateKey);
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

          // Update group once after member leave
          groupsBloc.add(RefreshGroups());

        } catch (e) {
          Logger.error(_tag, 'Error processing group member leave: $e');
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

  void _processInitialSync(SyncUpdate response) {
    // Update Invites
    response.rooms?.invite?.forEach((roomId, inviteUpdate) {
      _processInvite(roomId, inviteUpdate);
    });

    // If needed, process the joined/left rooms in the response
    response.rooms?.join?.forEach((roomId, joinedRoomUpdate) {
      _processRoomMessages(roomId, joinedRoomUpdate);
      if ((joinedRoomUpdate.state ?? []).isNotEmpty) {
        _processRoomJoin(roomId, joinedRoomUpdate);
      }
    });
    response.rooms?.leave?.forEach((roomId, leftRoomUpdate) {
      _processRoomLeaveOrKick(roomId, leftRoomUpdate);
    });

    // Finally, process the full client.rooms if you like
    for (var room in client.rooms) {
      // Only process rooms that the user has joined
      if (room.membership == Membership.join) {
        initialProcessRoom(room);
      }
    }

    // Refresh contacts
    contactsBloc.add(LoadContacts());

    notifyListeners();
  }

  Future<void> initialProcessRoom(Room room) async {
    // Check if the user has actually joined this room
    if (room.membership != Membership.join) {
      print('Skipping room ${room.id} - membership status: ${room.membership}');
      return;
    }

    await processJoinedRoom(room);
  }

  Future<void> processJoinedRoom(Room room) async {
    // Check if the room already exists
    final existingRoom = await roomRepository.getRoomById(room.id);

    final isDirect = utils.isDirectRoom(room.name ?? '');
    final customRoom = GridRoom.Room(
      roomId: room.id,
      name: room.name ?? 'Unnamed Room',
      isGroup: !isDirect,
      lastActivity: DateTime.now().toIso8601String(),
      avatarUrl: room.avatar?.toString(),
      members: room.getParticipants().map((p) => p.id).toList(),
      expirationTimestamp: utils.extractExpirationTimestamp(room.name ?? ''),
    );

    if (existingRoom == null) {
      // Insert new room
      await roomRepository.insertRoom(customRoom);
      Logger.info(_tag, 'Room created', data: {'roomId': room.id, 'name': customRoom.name});
    } else {
      // Update existing room
      await roomRepository.updateRoom(customRoom);
      Logger.debug(_tag, 'Room updated', data: {'roomId': room.id});
    }

    // Sync participants
    final currentParticipants = customRoom.members;
    final existingParticipants = await roomRepository.getRoomParticipants(room.id);
    
    // Track if this is a group room (do this once, outside the loop)
    final isGroupRoom = customRoom.isGroup;
    bool shouldUpdateGroup = false;

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

        if (isDirect) {
          final existingPrefs =
          await sharingPreferencesRepository.getSharingPreferences(participantId, 'user');
          if (existingPrefs == null) {
            final defaultPrefs = SharingPreferences(
              targetId: participantId,
              targetType: 'user',
              activeSharing: true,
              shareWindows: [],
            );
            await sharingPreferencesRepository.setSharingPreferences(defaultPrefs);
          }
        }

        // Handle group preferences only once per room
        if (isGroupRoom) {
          final existingGroupPrefs =
          await sharingPreferencesRepository.getSharingPreferences(room.id, 'group');
          if (existingGroupPrefs == null) {
            final defaultGroupPrefs = SharingPreferences(
              targetId: room.id,
              targetType: 'group',
              activeSharing: true,
              shareWindows: [],
            );
            await sharingPreferencesRepository.setSharingPreferences(
                defaultGroupPrefs);
          }
          shouldUpdateGroup = true;  // Mark that we need to update the group bloc
        }
        Logger.debug(_tag, 'User processed', data: {'userId': participantId, 'roomId': room.id});
        
        // If this is a direct room and someone other than us just joined, share location
        if (isDirect && participantId != client.userID && !existingParticipants.contains(participantId)) {
          Logger.info(_tag, 'New user joined direct room', data: {'userId': participantId, 'roomId': room.id});
          await roomService.shareCurrentLocationToRoom(room.id);
        }
      } catch (e) {
        Logger.error(_tag, 'Error fetching user profile: $e', data: {'userId': participantId});
      }
    }

    // Remove participants who are no longer in the room
    for (var participant in existingParticipants) {
      if (!currentParticipants.contains(participant)) {
        await roomRepository.removeRoomParticipant(room.id, participant);
        Logger.debug(_tag, 'Removed participant', data: {'userId': participant, 'roomId': room.id});
      }
    }
    
    // Update group bloc only once after processing all participants
    if (shouldUpdateGroup && isGroupRoom) {
      Logger.debug(_tag, 'Updating group in bloc', data: {'roomId': room.id});
      groupsBloc.add(UpdateGroup(room.id));
    }
  }

  Future<void> acceptInviteAndSync(String roomId) async {
    try {
      // Join the room
      final didJoin = await roomService.acceptInvitation(roomId);

      if (didJoin) {
        print('Successfully joined room $roomId');
        
        // Remove the invite immediately after accepting
        removeInvite(roomId);

        // Trigger a sync first to update room membership status
        await client.sync(timeout: 10000);
        print('Sync completed for room $roomId');

        // Now process the room after sync has updated membership
        final room = client.getRoomById(roomId);
        if (room != null) {
          // Force process the room even if membership hasn't updated yet
          await processJoinedRoom(room);
        }
        
        // Refresh groups to show the new room
        groupsBloc.add(RefreshGroups());
        groupsBloc.add(LoadGroups());
        
        // Additional delayed refreshes to ensure UI updates
        Future.delayed(const Duration(milliseconds: 200), () {
          groupsBloc.add(RefreshGroups());
          groupsBloc.add(LoadGroups());
        });
        
        Future.delayed(const Duration(milliseconds: 500), () {
          groupsBloc.add(RefreshGroups());
          groupsBloc.add(LoadGroups());
        });
      } else {
        throw Exception('Failed to join room');
      }
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

  Future<bool> _isServerReachable() async {
    try {
      // Try to check homeserver connectivity
      final homeserverUrl = client.homeserver;
      if (homeserverUrl == null) {
        print("[SyncManager] No homeserver URL configured");
        return false;
      }
      
      // Use the Matrix client's built-in connectivity check
      await client.checkHomeserver(homeserverUrl);
      
      // Also verify we're logged in and can make authenticated requests
      if (!client.isLogged()) {
        print("[SyncManager] Client is not logged in");
        return false;
      }
      
      // Try a simple authenticated request to verify token is valid
      try {
        await client.getAccountData(client.userID!, 'm.push_rules');
        return true;
      } catch (e) {
        // If we can't get account data, try to get our own profile as a fallback
        await client.getUserProfile(client.userID!);
        return true;
      }
    } catch (e) {
      print("[SyncManager] Server connectivity check failed: $e");
      return false;
    }
  }

  Future<void> _reconcileLocalStateWithServer() async {
    print("[SyncManager] Starting reconciliation check...");
    
    try {
      // CRITICAL: First verify server is reachable
      final isReachable = await _isServerReachable();
      if (!isReachable) {
        print("[SyncManager] Server is not reachable, skipping reconciliation");
        return;
      }
      
      print("[SyncManager] Server is reachable, proceeding with reconciliation");
      
      // 1. Get all joined rooms from server
      final serverRooms = client.rooms.where((room) => room.membership == Membership.join).toList();
      
      // Sanity check: If server returns 0 rooms but we have rooms locally,
      // this might indicate an issue rather than the user having no rooms
      final localRooms = await roomRepository.getAllRooms();
      if (serverRooms.isEmpty && localRooms.isNotEmpty) {
        print("[SyncManager] WARNING: Server returned 0 rooms but local has ${localRooms.length} rooms");
        print("[SyncManager] This might indicate a sync issue, skipping reconciliation");
        return;
      }
      
      final serverRoomIds = serverRooms.map((r) => r.id).toSet();
      final localRoomIds = localRooms.map((r) => r.roomId).toSet();
      
      // 2. Find discrepancies
      final roomsOnServerButNotLocal = serverRoomIds.difference(localRoomIds);
      final roomsInLocalButNotServer = localRoomIds.difference(serverRoomIds);
      
      print("[SyncManager] Reconciliation summary:");
      print("  - Server rooms: ${serverRoomIds.length}");
      print("  - Local rooms: ${localRoomIds.length}");
      print("  - Missing locally: ${roomsOnServerButNotLocal.length}");
      print("  - Extra locally: ${roomsInLocalButNotServer.length}");
      
      // 3. Add missing rooms from server
      for (final roomId in roomsOnServerButNotLocal) {
        print("[SyncManager] Adding missing room: $roomId");
        final serverRoom = serverRooms.firstWhere((r) => r.id == roomId);
        await processJoinedRoom(serverRoom);
      }
      
      // 4. Remove rooms that don't exist on server (with additional safety check)
      for (final roomId in roomsInLocalButNotServer) {
        // Double-check this room really doesn't exist on server
        try {
          final room = client.getRoomById(roomId);
          if (room != null && room.membership == Membership.join) {
            print("[SyncManager] Room $roomId actually exists on server, skipping removal");
            continue;
          }
        } catch (e) {
          // Room lookup failed, proceed with removal
        }
        
        print("[SyncManager] Removing orphaned room: $roomId");
        await roomRepository.deleteRoom(roomId);
        await roomRepository.removeAllParticipants(roomId);
      }
      
      // 5. Verify room members for existing rooms
      for (final serverRoom in serverRooms) {
        if (localRoomIds.contains(serverRoom.id)) {
          await _reconcileRoomMembers(serverRoom);
        }
      }
      
      // 6. Clean up orphaned users
      await _cleanupOrphanedUsers();
      
      // 7. Clean up orphaned relationships (only for rooms confirmed not on server)
      final validServerRoomIds = serverRooms.map((r) => r.id).toSet();
      final cleanedRelationships = await userRepository.cleanupOrphanedRelationships(validServerRoomIds);
      if (cleanedRelationships > 0) {
        print("[SyncManager] Cleaned up $cleanedRelationships orphaned user relationships");
      }
      
      // 8. Refresh UI
      contactsBloc.add(RefreshContacts());
      groupsBloc.add(RefreshGroups());
      mapBloc.add(MapLoadUserLocations());
      
      print("[SyncManager] Reconciliation complete");
      
    } catch (e) {
      print("[SyncManager] Error during reconciliation: $e");
      // Continue with normal sync even if reconciliation fails
    }
  }
  
  Future<void> _reconcileRoomMembers(Room serverRoom) async {
    try {
      final localRoom = await roomRepository.getRoomById(serverRoom.id);
      if (localRoom == null) return;
      
      final serverMembers = serverRoom.getParticipants()
          .where((p) => p.membership == Membership.join)
          .map((p) => p.id)
          .toSet();
      final localMembers = localRoom.members.toSet();
      
      final missingLocally = serverMembers.difference(localMembers);
      final extraLocally = localMembers.difference(serverMembers);
      
      if (missingLocally.isNotEmpty || extraLocally.isNotEmpty) {
        print("[SyncManager] Room ${serverRoom.id} member mismatch:");
        print("  - Missing locally: $missingLocally");
        print("  - Extra locally: $extraLocally");
        
        // Update room with correct member list
        final updatedRoom = GridRoom.Room(
          roomId: localRoom.roomId,
          name: localRoom.name,
          isGroup: localRoom.isGroup,
          lastActivity: localRoom.lastActivity,
          avatarUrl: localRoom.avatarUrl,
          members: serverMembers.toList(),
          expirationTimestamp: localRoom.expirationTimestamp,
        );
        await roomRepository.updateRoom(updatedRoom);
        
        // Add missing members
        for (final memberId in missingLocally) {
          try {
            final profileInfo = await client.getUserProfile(memberId);
            final gridUser = GridUser.GridUser(
              userId: memberId,
              displayName: profileInfo.displayname,
              avatarUrl: profileInfo.avatarUrl?.toString(),
              lastSeen: DateTime.now().toIso8601String(),
              profileStatus: "",
            );
            await userRepository.insertUser(gridUser);
            
            String? membershipStatus;
            if (localRoom.isGroup) {
              membershipStatus = await roomService.getUserRoomMembership(serverRoom.id, memberId) ?? 'joined';
            }
            
            await userRepository.insertUserRelationship(
              memberId,
              serverRoom.id,
              !localRoom.isGroup,
              membershipStatus: membershipStatus,
            );
          } catch (e) {
            print("[SyncManager] Error adding member $memberId: $e");
          }
        }
        
        // Remove extra members
        for (final memberId in extraLocally) {
          await userRepository.removeUserRelationship(memberId, serverRoom.id);
          await roomRepository.removeRoomParticipant(serverRoom.id, memberId);
        }
      }
    } catch (e) {
      print("[SyncManager] Error reconciling room members: $e");
    }
  }
  
  Future<void> _cleanupOrphanedUsers() async {
    try {
      // Get all users from database
      final allUsers = await userRepository.getAllUsers();
      
      for (final user in allUsers) {
        // Skip own user
        if (user.userId == client.userID) continue;
        
        // Check if user exists in any rooms or as a contact
        final userRooms = await roomRepository.getUserRooms(user.userId);
        final directRoom = await userRepository.getDirectRoomForContact(user.userId);
        
        if (userRooms.isEmpty && directRoom == null) {
          print("[SyncManager] Removing orphaned user: ${user.userId}");
          await locationRepository.deleteUserLocations(user.userId);
          await userRepository.deleteUser(user.userId);
          mapBloc.add(RemoveUserLocation(user.userId));
        }
      }
    } catch (e) {
      print("[SyncManager] Error cleaning up orphaned users: $e");
    }
  }
}
