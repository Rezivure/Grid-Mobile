import 'dart:async';
import 'dart:ffi';
import 'dart:math';

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/services/user_service.dart';
import 'package:matrix/matrix_api_lite/generated/model.dart' as matrix_model;
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/location_history_repository.dart';
import 'package:grid_frontend/repositories/room_location_history_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_manager.dart';
import 'package:grid_frontend/models/room.dart' as GridRoom;

class RoomService {
  final UserService userService;
  final Client client;
  final UserRepository userRepository;
  final UserKeysRepository userKeysRepository;
  final RoomRepository roomRepository;
  final LocationRepository locationRepository;
  final LocationHistoryRepository locationHistoryRepository;
  final RoomLocationHistoryRepository? roomLocationHistoryRepository;
  final SharingPreferencesRepository sharingPreferencesRepository;

  // Tracks recent messages/location updates sent to prevent redundant messages
  final Map<String, Set<String>> _recentlySentMessages = {};
  final int _maxMessageHistory = 50;

  bg.Location? _currentLocation;
  DateTime? _lastUpdateTime;
  
  bg.Location? get currentLocation => _currentLocation;



  RoomService(
      this.client,
      this.userService,
      this.userRepository,
      this.userKeysRepository,
      this.roomRepository,
      this.locationRepository,
      this.locationHistoryRepository,
      this.sharingPreferencesRepository,
      LocationManager locationManager, // Inject LocationManager
      {this.roomLocationHistoryRepository}
      ) {
    // Subscribe to location updates
    locationManager.locationStream.listen((location) {
      // Update current location in room service
      _currentLocation = location;
      // Defer updates until appropriate time
      _handleLocationUpdate(location);
    });
  }
  
  void _handleLocationUpdate(bg.Location location) {
    // Queue location updates intelligently
    // They will be processed when appropriate
    _queueLocationUpdate(location);
  }
  
  Timer? _locationUpdateTimer;
  bg.Location? _pendingLocation;
  
  void _queueLocationUpdate(bg.Location location) {
    _pendingLocation = location;
    
    // Cancel any existing timer
    _locationUpdateTimer?.cancel();
    
    // Debounce location updates by 1 second to prevent spam
    _locationUpdateTimer = Timer(const Duration(seconds: 1), () {
      if (_pendingLocation != null) {
        updateRooms(_pendingLocation!);
        _pendingLocation = null;
      }
    });
  }


  String getMyHomeserver() {
    return client.homeserver.toString();
  }

 /// create direct grid room (contact)
  Future<bool> createRoomAndInviteContact(String matrixUserId) async {



    // Check if the user exists
    try {
      final exists = await userService.userExists(matrixUserId);
      if (!exists) {
        return false;
      }
    } catch (e) {
      print('User $matrixUserId does not exist: $e');
      return false;
    }

    // Check if direct grid contact already exists
    final myUserId = client.userID ?? 'error';

    // Use full Matrix IDs for relationship check to match getRelationshipStatus
    RelationshipStatus status = await userService.getRelationshipStatus(myUserId, matrixUserId);

    if (status == RelationshipStatus.canInvite) {
      final roomName = "Grid:Direct:$myUserId:$matrixUserId";
      final roomId = await client.createRoom(
        name: roomName,
        isDirect: true,
        preset: CreateRoomPreset.privateChat,
        invite: [matrixUserId],
        initialState: [
          StateEvent(
            type: 'm.room.encryption',
            content: {"algorithm": "m.megolm.v1.aes-sha2"},
          ),
        ],
      );
      
      // Room created with invite - now we need to handle it immediately
      // Note: invite is already sent via createRoom parameters
      
      return true; // success
    }
    return false; // failed
  }
  Future<bool> isUserInRoom(String roomId, String userId) async {
    Room? room = client.getRoomById(roomId);
    if (room != null) {
      var participants = room.getParticipants();
      return participants.any((user) => user.id == userId);
    }
    return false;
  }


  // In RoomService
  Future<String?> getUserRoomMembership(String roomId, String userId) async {
    Room? room = client.getRoomById(roomId);
    if (room != null) {
      // Check all members, not just joined participants
      try {
        // First try to get from the room state directly
        final memberEvent = room.getState('m.room.member', userId);
        if (memberEvent != null) {
          final membership = memberEvent.content['membership'] as String?;
          print("RoomService: User $userId membership from state in room $roomId: $membership");
          return membership;
        }
      } catch (e) {
        print("RoomService: Failed to get membership from state: $e");
      }
      
      // Fallback to participants list
      var participants = room.getParticipants();
      try {
        final participant = participants.firstWhere(
              (user) => user.id == userId,
        );
        final membershipName = participant.membership.name;
        print("RoomService: User $userId membership from participants in room $roomId: $membershipName");
        return membershipName;
      } catch (e) {
        print("RoomService: User $userId not found in participants, checking if room was just created");
        
        // If this is a direct room that was just created, the invited user might not appear
        // in participants yet, so we assume they're invited
        final roomName = room.name ?? '';
        if (roomName.startsWith('Grid:Direct:')) {
          print("RoomService: Direct room detected, assuming user $userId is invited");
          return 'invite';
        }
        
        print("RoomService: User $userId not found, returning null");
        return null;
      }
    }
    return null;
  }

  /// Leaves a room
  Future<bool> leaveRoom(String roomId) async {
    try {
      final userId = await getMyUserId();
      if (userId == null) {
        throw Exception('User ID not found');
      }

      final room = client.getRoomById(roomId);
      if (room != null) {
        try {
          await room.leave();
          await client.forgetRoom(roomId); // Add this line
        } catch (e) {
          print('Error leaving Matrix room (continuing with local cleanup): $e');
        }
      }

      // Delete all map icons associated with this room
      try {
        final databaseService = DatabaseService();
        final mapIconRepository = MapIconRepository(databaseService);
        await mapIconRepository.deleteIconsForRoom(roomId);
        print('Deleted map icons for room: $roomId');
      } catch (e) {
        print('Error deleting map icons for room $roomId: $e');
      }

      await roomRepository.leaveRoom(roomId, userId);
      return true;
    } catch (e) {
      print('Error in leaveRoom: $e');
      return false;
    }
  }

  int getUserPowerLevel(String roomId, String userId) {
    final room = client.getRoomById(roomId);
    if (room != null) {
      final powerLevel = room.getPowerLevelByUserId(userId);
      return powerLevel;
    }
    return 0;
  }


  List<User> getFilteredParticipants(Room room, String searchText) {
    final lowerSearchText = searchText.toLowerCase();
    return room
        .getParticipants()
        .where((user) =>
    user.id != client.userID &&
        (user.displayName ?? user.id).toLowerCase().contains(lowerSearchText))
        .toList();
  }

  /// Fetches the list of participants in a room
  Future<List<User>> getRoomParticipants(String roomId) async {
    try {
      final room = client.getRoomById(roomId);
      if (room == null) {
        throw Exception('Room not found');
      }
      return await room.getParticipants();
    } catch (e) {
      print('Error fetching room participants: $e');
      rethrow;
    }
  }

  int getPowerLevelByUserId(Room room, String userId) {
    return room.getPowerLevelByUserId(userId);
  }

  Future<List<Map<String, dynamic>>> getGroupRooms() async {
    try {
      List<Map<String, dynamic>> groupRooms = [];

      for (var room in client.rooms) {
        final participants = await room.getParticipants();
        if (room.name.contains("Grid:Group") &&
            room.membership == Membership.join) {
          groupRooms.add({
            'room': room,
            'participants': participants,
          });
        }
      }

      return groupRooms;
    } catch (e) {
      print("Error getting group rooms: $e");
      return [];
    }
  }

  Future<int> getNumInvites() async {
    try {
      List<Room> invitedRooms = client.rooms.where((room) =>
      room.membership == Membership.invite).toList();
      return invitedRooms.length;
    } catch (e) {
      print("Error fetching invites: $e");
      return 0;
    }
  }

  Future<bool> acceptInvitation(String roomId) async {
    try {
      print("Attempting to join room: $roomId");

      // Attempt to join the room
      await client.joinRoom(roomId);
      print("Successfully joined room: $roomId");

      // Wait a bit for sync to catch up
      await Future.delayed(const Duration(seconds: 1));
      
      // Check if the room exists
      final room = client.getRoomById(roomId);
      if (room == null) {
        print("Room not found after joining - might be sync delay.");
        // Don't auto-leave - might just need more time to sync
        return false; // Invalid invite
      }

      // Check participants - but be more lenient
      final participants = await room.getParticipants();
      final joinedParticipants = participants.where(
        (user) => user.membership == Membership.join
      ).toList();
      
      // Check for invited participants too (they might not have joined yet)
      final invitedParticipants = participants.where(
        (user) => user.membership == Membership.invite && user.id != client.userID
      ).toList();
      
      if (joinedParticipants.length == 1 && 
          joinedParticipants.first.id == client.userID &&
          invitedParticipants.isEmpty) {
        // We're alone and no one is invited - this is actually invalid
        print("No valid participants found, leaving the room.");
        await leaveRoom(roomId);
        return false; // Invalid invite
      }
      
      return true; // Successfully joined
    } catch (e) {
      print("Error during acceptInvitation: $e");
      // Don't auto-leave on error - could be network issue
      // Let the cleanup process handle it later if needed
      return false; // Failed to join but don't leave
    }
  }

  Future<void> declineInvitation(String roomId) async {
    try {
      await client.leaveRoom(roomId);
    } catch (e) {
      print("Error declining invitation: $e");
    }
  }

  Future<bool> checkIfInRoom(String roomId) async {
    try {
      final roomExists = client.rooms.any((room) => room.id == roomId);
      if (roomExists) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      print("Failed to check if room exists");
      return false;
    }
  }

  Future<void> cleanRooms() async {
    try {
      // SAFETY: Ensure client is fully synced before cleaning
      if (!client.isLogged() || client.syncPending == null) {
        print("[CleanRooms] Client not fully synced yet, skipping cleanup");
        return;
      }
      
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final myUserId = client.userID;
      print("Checking for rooms to clean at timestamp: $now");

      // Create a copy of the rooms list to avoid concurrent modification
      final roomsList = List.from(client.rooms);
      
      for (var room in roomsList) {
        // Skip rooms we're not actually joined to
        if (room.membership != Membership.join) {
          continue;
        }
        
        print("Trying to get rooms");
        final participants = await room.getParticipants();
        bool shouldLeave = false;
        String leaveReason = '';

        // Check if it's a Grid room (direct or group)
        if (room.name.startsWith("Grid:")) {
          print("Checking Grid room: ${room.name}");

          if (room.name.contains("Grid:Group:")) {
            final roomNameParts = room.name.split(":");
            if (roomNameParts.length >= 4) {
              final expirationTimestamp = int.tryParse(roomNameParts[2]) ?? 0;
              print("Group room ${room.id} expiration: $expirationTimestamp");

              if (expirationTimestamp > 0 && expirationTimestamp < now) {
                shouldLeave = true;
                leaveReason = 'expired group';
              }
            }
          } else if (room.name.contains("Grid:Direct:")) {
            print("Checking direct room: ${room.id} with ${participants.length} participants");
            
            // Get joined members only
            final joinedMembers = participants.where((p) => p.membership == Membership.join).toList();
            
            // For direct rooms, if you're alone, leave
            if (joinedMembers.length == 1 && joinedMembers.first.id == myUserId) {
              shouldLeave = true;
              leaveReason = 'alone in direct room - other user left';
            } else if (joinedMembers.isEmpty) {
              // No one has join status
              shouldLeave = true;
              leaveReason = 'no active participants in direct room';
            }
          }
        } else {
          print("Found non-Grid room: ${room.name}");
          shouldLeave = true;
          leaveReason = 'non-Grid room';
        }

        // No extra checks needed - the logic above handles all cases

        if (shouldLeave) {
          try {
            print("Leaving room ${room.id} (${room.name}) - Reason: $leaveReason");

            // Leave and forget the room on the server first
            await room.leave();
            await client.forgetRoom(room.id);
            print('Attempted to leave room: ${room.id}, verifying...');

            // Confirm the room is left by re-fetching the joined rooms
            final joinedRooms = await client.getJoinedRooms();
            if (!joinedRooms.contains(room.id)) {
              print('Confirmed room ${room.id} left successfully.');

              // Only clean up locally if the leave was successful
              final removedUserIds = await _cleanupLocalData(room.id, participants);
              
              // Note: Map cleanup needs to be handled by SyncManager or other components
              // that have access to MapBloc. They can listen for room leave events
              // or user deletion events to update the map accordingly.
              print('Successfully cleaned up local data for room: ${room.id}, removed users: $removedUserIds');
            } else {
              print('Room ${room.id} still appears in joined rooms after leave attempt.');
            }
          } catch (e) {
            print('Error leaving room ${room.id}: $e');
          }
        } else {
          print("Keeping room ${room.id} (${room.name})");
        }
      }
      print("Room cleanup completed");
    } catch (e) {
      print("Error during room cleanup: $e");
    }
  }


  /// Handles cleanup of local data when leaving a room
  /// Returns list of user IDs that were removed from the system
  Future<List<String>> _cleanupLocalData(String roomId, List<User> matrixUsers) async {
    final removedUserIds = <String>[];
    try {
      print("Starting local cleanup for room: $roomId");

      // Delete all map icons associated with this room
      try {
        final databaseService = DatabaseService();
        final mapIconRepository = MapIconRepository(databaseService);
        await mapIconRepository.deleteIconsForRoom(roomId);
        print('Deleted map icons for room: $roomId');
      } catch (e) {
        print('Error deleting map icons for room $roomId: $e');
      }

      // Get all user IDs in the room before deletion
      final userIds = matrixUsers.map((p) => p.id).toList();

      // Get list of direct contacts (these are already GridUsers)
      final directContacts = await userRepository.getDirectContacts();
      final directContactIds = directContacts.map((contact) => contact.userId).toSet();

      // Start with removing room participants
      await roomRepository.removeAllParticipants(roomId);

      // For each user in the room
      for (final userId in userIds) {
        // Skip ourselves
        if (userId == client.userID) {
          continue;
        }
        
        // Remove the relationship for this room
        await userRepository.removeUserRelationship(userId, roomId);
        
        // Check if user has any other rooms
        final otherRooms = await userRepository.getUserRooms(userId);
        otherRooms.remove(roomId); // Remove current room from list

        if (otherRooms.isEmpty) {
          print("User $userId has no other rooms, cleaning up user data and location");
          // Remove user's location data
          await locationRepository.deleteUserLocations(userId);
          
          // Track that we removed this user
          removedUserIds.add(userId);
          
          // Remove user and their relationships (this handles both GridUser and relationships)
          await userRepository.deleteUser(userId);
          
          // Note: The map will be updated by SyncManager's _cleanupOrphanedUsers
          // which is called after room cleanup during reconciliation
        } else {
          print("User $userId exists in other rooms (${otherRooms.length}), keeping user data");
        }
      }

      // Finally delete the room itself
      await roomRepository.deleteRoom(roomId);

      print("Completed local cleanup for room: $roomId, removed ${removedUserIds.length} users");
      return removedUserIds;
    } catch (e) {
      print("Error during local cleanup for room $roomId: $e");
      // Re-throw the error to be handled by the calling function
      rethrow;
    }
  }

  Future<String> createGroup(String groupName, List<String> userIds, int durationInHours) async {
    final effectiveUserId = client.userID ?? client.userID?.localpart;
    if (effectiveUserId == null) {
      throw Exception('Unable to determine current user ID');
    }

    final int expirationTimestamp = durationInHours == 0
        ? 0
        : DateTime.now().add(Duration(hours: durationInHours)).millisecondsSinceEpoch ~/ 1000;

    final roomName = 'Grid:Group:$expirationTimestamp:$groupName:$effectiveUserId';

    // power-levels config: only admins (creator) can invite/kick/etc.
    final powerLevelsContent = {
      'ban': 50,
      'events': {
        'm.room.name': 50,
        'm.room.power_levels': 100,
        'm.room.history_visibility': 100,
        'm.room.canonical_alias': 50,
        'm.room.avatar': 50,
        'm.room.tombstone': 100,
        'm.room.server_acl': 100,
        'm.room.encryption': 100,
      },
      'events_default': 0,
      'invite': 100,
      'kick': 100,
      'notifications': {'room': 50},
      'redact': 50,
      'state_default': 50,
      'users': {effectiveUserId: 100},
      'users_default': 0,
    };

    String roomId;
    try {
      roomId = await client.createRoom(
        name: roomName,
        isDirect: false,
        visibility: matrix_model.Visibility.private,
        initialState: [
          StateEvent(
            type: EventTypes.Encryption,
            content: {'algorithm': 'm.megolm.v1.aes-sha2'},
          ),
          StateEvent(
            type: EventTypes.RoomPowerLevels,
            content: powerLevelsContent,
          ),
        ],
      );

      for (final user in userIds) {
        var fullMatrixId = user;
        final isCustomServ = isCustomHomeserver();
        if (isCustomServ) {
          fullMatrixId = '@$fullMatrixId';
        } else {
          final homeserver = getMyHomeserver().replaceFirst('https://', '');
          fullMatrixId = '@$user:$homeserver';
        }
        await client.inviteUser(roomId, fullMatrixId);
      }

      await client.setRoomTag(effectiveUserId, roomId, 'Grid Group');
    } catch (e) {
      throw Exception('Failed to create group: $e');
    }

    return roomId;
  }


  bool isCustomHomeserver() {
    final homeserver = getMyHomeserver();
    return utils.isCustomHomeserver(homeserver);
  }

  void getAndUpdateDisplayName() async {

    final prefs = await SharedPreferences.getInstance();
    var userID = client.userID ?? "";
    var displayName = await client.getDisplayName(userID) ?? '';
    if (displayName != null) {
      prefs.setString('displayName', displayName);
    }
  }

  void sendLocationEvent(String roomId, bg.Location location) async {
    final room = client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      print("Skipping location update for room $roomId - no longer a member");
      return;
    }
    if (room != null) {
      final latitude = location.coords.latitude;
      final longitude = location.coords.longitude;

      if (latitude != null && longitude != null) {
        // Create a unique hash for the location message
        var timestamp = DateTime.now().millisecondsSinceEpoch;

        final messageHash = '$latitude:$longitude:$timestamp';

        // Check if the message is already sent
        if (_recentlySentMessages[roomId]?.contains(messageHash) == true) {
          print("Duplicate location event skipped for room $roomId");
          return;
        }

        // Build the event content
        final eventContent = {
          'msgtype': 'm.location',
          'body': 'Current location',
          'geo_uri': 'geo:$latitude,$longitude',
          'description': 'Current location',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        };

        try {
          await room.sendEvent(eventContent);
          print("Location event sent to room $roomId: ${room.name}  $latitude, $longitude");

          // Track the sent message
          _recentlySentMessages.putIfAbsent(roomId, () => {}).add(messageHash);

          // Trim history if needed
          if (_recentlySentMessages[roomId]!.length > _maxMessageHistory) {
            _recentlySentMessages[roomId]!.remove(_recentlySentMessages[roomId]!.first);
          }
          
          // Save to room-specific location history
          final myUserId = client.userID;
          if (myUserId != null) {
            // Save to room-specific history
            if (roomLocationHistoryRepository != null) {
              await roomLocationHistoryRepository!.addLocationPoint(
                roomId: roomId,
                userId: myUserId,
                latitude: latitude,
                longitude: longitude,
              );
            }
            
            // Also save to legacy global history (can be deprecated later)
            await locationHistoryRepository.addLocationPoint(myUserId, latitude, longitude);
          }
        } catch (e) {
          print("Failed to send location event: $e");
        }
      } else {
        print("Latitude or Longitude is null");
      }
    } else {
      print("Room $roomId not found");
    }
  }

  Future<int> getRoomMemberCount(String roomId) async {
    final room = client.getRoomById(roomId);
    if (room == null) return 0;

    return room
        .getParticipants()
        .where((member) =>
    member.membership == Membership.join ||
        member.membership == Membership.invite)
        .length;
  }

  Future<void> updateRooms(bg.Location location) async {
    // Prevent rapid duplicate updates
    final now = DateTime.now();
    if (_lastUpdateTime != null && 
        now.difference(_lastUpdateTime!).inSeconds < 3) {
      print("[RoomService] Skipping duplicate room update (too soon after last update)");
      return;
    }
    _lastUpdateTime = now;
    
    List<Room> rooms = client.rooms.where((r) => r.membership == Membership.join).toList();
    print("Grid: Found ${rooms.length} total rooms to process (filtered for joined only)");

    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (Room room in rooms) {
      try {
        print("Grid: Processing room ${room.name} (${room.id})");

        // Skip non-Grid rooms
        if (!room.name.startsWith('Grid:')) {
          print("Grid: Skipping non-Grid room: ${room.name}");
          continue;
        }

        // Handle different room types
        if (room.name.startsWith('Grid:Group:')) {
          // Process group rooms
          final parts = room.name.split(':');
          if (parts.length < 3) continue;

          final expirationStr = parts[2];
          final expirationTimestamp = int.tryParse(expirationStr);
          print("Grid: Group room expiration: $expirationTimestamp, current: $currentTimestamp");

          // Skip expired group rooms
          if (expirationTimestamp != null &&
              expirationTimestamp != 0 &&
              expirationTimestamp < currentTimestamp) {
            print("Grid: Skipping expired group room");
            continue;
          }
        } else if (!room.name.startsWith('Grid:Direct:')) {
          print("Grid: Skipping unknown Grid room type: ${room.name}");
          continue;
        }

        // Get joined members and log
        var joinedMembers = room
            .getParticipants()
            .where((member) => member.membership == Membership.join)
            .toList();
        print("Grid: Room has ${joinedMembers.length} joined members");

        if (!joinedMembers.any((member) => member.id == getMyUserId())) {
          print("Grid: Skipping room ${room.id} - I am not a joined member");
          continue;
        }

        if (joinedMembers.length > 1) {

          if (joinedMembers.length == 2 && room.name.startsWith('Grid:Direct:')) {
            final myUserId = getMyUserId();
            var otherUsers = joinedMembers.where((member) =>
            member.id != myUserId);
            var otherUser = otherUsers.first.id;
            final isSharing = await userService.isInSharingWindow(otherUser);
            if (!isSharing) {
              print("Grid: Skipping direct room ${room
                  .id} - not in sharing window with $otherUser");
              continue;
            } else {
              print("In sharing window");
            }
          }

          if (joinedMembers.length >= 2 && room.name.startsWith('Grid:Group:')) {

            final isSharing = await userService.isGroupInSharingWindow(room.id);
            if (!isSharing) {
              print("Grid: Skipping group room ${room
                  .id} - not in sharing window.");
              continue;
            } else {
              print("In sharing window");
            }
          }


          print("Grid: Sending location event to room ${room.id} / ${room.name}");
          sendLocationEvent(room.id, location);
          print("Grid: Location event sent successfully");
        } else {
          print("Grid: Skipping room ${room.id} - insufficient members");
        }

      } catch (e) {
        print('Error processing room ${room.name}: $e');
        continue;
      }
    }
  }

// Helper method to check if a room is expired
  bool isRoomExpired(String roomName) {
    try {
      if (!roomName.startsWith('Grid:Group:')) return true;

      final parts = roomName.split(':');
      if (parts.length < 3) return true;

      final expirationStr = parts[2];
      final expirationTimestamp = int.tryParse(expirationStr);

      if (expirationTimestamp == null) return true;
      if (expirationTimestamp == 0) return false; // 0 means no expiration

      final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return expirationTimestamp < currentTimestamp;
    } catch (e) {
      return true; // If there's any error parsing, consider the room expired
    }
  }

  Future<bool> kickMemberFromRoom(String roomId, String userId) async {
    final room = client.getRoomById(roomId);
    if (room != null && room.canKick) {
      try {
        await room.kick(userId);
        print("Successfully kicked user $userId from room $roomId");
      } catch (e) {
        print("Failed to remove member: $e");
        return false;
      }
      return true;
    }
    return false;
  }

  Future<void> updateSingleRoom(String roomId) async {
    final room = client.getRoomById(roomId);
    if (room != null && currentLocation != null) {
      // Verify it's a valid room to send to (direct room or group)
      var joinedMembers = room
          .getParticipants()
          .where((member) => member.membership == Membership.join)
          .toList();

      if (joinedMembers.length >= 2) {  // Valid room with at least 2 members
        sendLocationEvent(roomId, currentLocation!);
      }
    }
  }

  Map<String, Map<String, String>> getUserDeviceKeys(String userId) {
    final userDeviceKeys = client.userDeviceKeys[userId]?.deviceKeys.values;
    Map<String, Map<String, String>> deviceKeysMap = {};

    if (userDeviceKeys != null) {
      for (final deviceKeyEntry in userDeviceKeys) {
        final deviceId = deviceKeyEntry.deviceId;
        if (deviceId != null) {
          deviceKeysMap[deviceId] = {
            "curve25519": deviceKeyEntry.keys['curve25519:$deviceId'] ?? "",
            "ed25519": deviceKeyEntry.keys['ed25519:$deviceId'] ?? ""
          };
        }
      }
    }
    return deviceKeysMap;
  }

  Future<void> updateAllUsersDeviceKeys() async {
    final rooms = client.rooms;
    rooms.forEach((room) async => {
      await updateUsersInRoomKeysStatus(room)
    });
  }

  Future<void> addTag(String roomId, String tag, {double? order}) async {
    try {
      print("Attempting to add tag '$tag' to room ID $roomId");
      await client.setRoomTag(client.userID!, roomId, tag, order: order);
      print("Tag added successfully.");
    } catch (e) {
      print("Failed to add tag: $e");
    }
  }


  Future<bool> userHasNewDeviceKeys(String userId, Map<String, dynamic> newKeys) async {
    final curKeys = await userKeysRepository.getKeysByUserId(userId);

    if (curKeys == null) {
      // Log or handle cases where no keys exist for the user
      print("No existing keys found. Inserting new keys.");
      await userKeysRepository.upsertKeys(userId, newKeys['curve25519Key'], newKeys['ed25519Key']);
      return false; // No need to alert, as these are the first keys
    }

    // Check for new keys
    for (final key in newKeys.keys) {
      if (!curKeys.containsKey(key) || curKeys[key] != newKeys[key]) {
        return true; // New or updated key found
      }
    }

    // No new keys
    return false;
  }

  String? getMyUserId() {
    return client.userID;
  }
  Future<void> updateUsersInRoomKeysStatus(Room room) async {
    final members = room.getParticipants().where((member) => member.membership == Membership.join);

    for (final member in members) {
      // Get all device keys for the user
      final userDeviceKeys = getUserDeviceKeys(member.id);

      for (final deviceId in userDeviceKeys.keys) {
        final deviceKeys = userDeviceKeys[deviceId]!; // Keys for a specific device

        // Fetch existing keys for the user
        final existingKeys = await userKeysRepository.getKeysByUserId(member.id);

        if (existingKeys == null) {
          // No existing keys, insert the current device's keys
          await userKeysRepository.upsertKeys(
            member.id,
            deviceKeys['curve25519']!,
            deviceKeys['ed25519']!,
          );
        } else {
          // Check if the user has new or updated keys
          final hasNewKeys = await userHasNewDeviceKeys(member.id, deviceKeys);

          if (hasNewKeys) {
            // Update approval status (if applicable)
            // Example: Add this to UserKeysRepository if needed
            // await userKeysRepository.updateApprovalStatus(member.id, false);

            // Insert new keys to update the record
            await userKeysRepository.upsertKeys(
              member.id,
              deviceKeys['curve25519']!,
              deviceKeys['ed25519']!,
            );
          }
        }
      }
    }
  }

  Future<Map<String, dynamic>> getDirectRooms() async {
    try {
      List<User> directUsers = [];
      Map<User, String> userRoomMap = {};

      for (var room in client.rooms) {
        final participants = await room.getParticipants();

        // Find the current user's membership in the room.
        final ownMembership = participants
            .firstWhere((user) => user.id == client.userID)
            .membership;

        // Only include rooms where the current user has joined.
        if (room.name.contains("Grid:Direct") && ownMembership == Membership.join) {
          try {
            // Find the other member in the room (the one you are chatting with).
            final otherMember = participants.firstWhere(
                  (user) => user.id != client.userID,
            );

            // Only add if the other member has a valid membership status
            // Don't auto-leave here - this might just be a sync issue
            if (otherMember.membership == Membership.join || 
                otherMember.membership == Membership.invite) {
              directUsers.add(otherMember);
              userRoomMap[otherMember] = room.id;
            } else if (otherMember.membership == Membership.leave) {
              // Other person left - we can safely leave too
              print('Other member left room: ${room.id}, leaving as well');
              await leaveRoom(room.id);
            } else {
              // Unknown state - don't add but also don't leave yet
              print('Other member in unknown state in room: ${room.id}, skipping');
            }
          } catch (e) {
            // No other member found - but don't auto-leave!
            // This could be a temporary sync issue
            print('Warning: No other member found in room: ${room.id} (might be sync issue)');
            // Don't leave the room - just skip it for now
          }
        }
      }

      return {
        "users": directUsers,
        "userRoomMap": userRoomMap,
      };
    } catch (e) {
      print("Error getting direct rooms: $e");
      return {
        "users": [],
        "userRoomMap": {},
      };
    }
  }
}
