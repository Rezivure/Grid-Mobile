import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:matrix/matrix_api_lite/generated/model.dart' as matrix_model;
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'location_manager.dart';

class RoomService {
  final UserService userService;
  final Client client;
  final UserRepository userRepository;
  final UserKeysRepository userKeysRepository;
  final RoomRepository roomRepository;
  final LocationRepository locationRepository;
  final SharingPreferencesRepository sharingPreferencesRepository;

  // Tracks recent messages/location updates sent to prevent redundant messages
  final Map<String, Set<String>> _recentlySentMessages = {};
  final int _maxMessageHistory = 50;


  RoomService(
      this.client,
      this.userService,
      this.userRepository,
      this.userKeysRepository,
      this.roomRepository,
      this.locationRepository,
      this.sharingPreferencesRepository,
      LocationManager locationManager, // Inject LocationManager
      ) {
    // Subscribe to location updates
    locationManager.locationStream.listen((location) {
      _onNewLocation(location);
    });
  }

  void _onNewLocation(bg.Location location) {
    print("Sending updated location to all rooms");
    updateRooms(location);
  }

 /// create direct grid room (contact)
  Future<bool> createRoomAndInviteContact(String username) async {
    // Use the normalizeUser utility function
    final normalizedData = normalizeUser(username);
    final String matrixUserId = normalizedData['matrixUserId']!;

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
    final myUserId = client.userID?.localpart ?? 'error';
    final contactUserId = matrixUserId?.localpart ?? 'error';
    RelationshipStatus status = await userService.getRelationshipStatus(myUserId, contactUserId);

    if (status == RelationshipStatus.canInvite) {
      String? myUserId = client.userID;
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
      return true; // success
    }
    return false; // failed
  }

  Future<bool> isUserInRoom(String roomId, String userId) async {
    Room? room = client.getRoomById(roomId);
    if (room != null) {
      var participants = room.getParticipants();
      return participants.any((user) => user.id == userId && user.membership == Membership.join);
    }
    return false;
  }


  /// Leaves a room
  Future<bool> leaveRoom(String roomId) async {
    try {
      final room = client.getRoomById(roomId);
      if (room == null) {
        throw Exception('Room not found');
      }
      await room.leave();
      return true;
    } catch (e) {
      print('Error leaving room: $e');
      return false;
    }
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
      await client.sync();
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
      await client.sync();
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

      // Check if the room exists
      final room = client.getRoomById(roomId);
      if (room == null) {
        print("Room not found after joining.");
        return false; // Invalid invite
      }

      // Optionally, you can check participants
      final participants = await room.getParticipants();
      final hasValidParticipant = participants.any(
            (user) => user.membership == Membership.join && user.id != client.userID,
      );

      if (!hasValidParticipant) {
        print("No valid participants found, leaving the room.");
        await leaveRoom(roomId);
        return false; // Invalid invite
      }
      return true; // Successfully joined
    } catch (e) {
      print("Error during acceptInvitation: $e");
      await leaveRoom(roomId);
      return false; // Failed to join
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
    // removes expired rooms and rooms that are basically
    // abandoned, could probably use api/sdk to better detect
    // abandoned rooms
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000; // Current timestamp in Unix format

      for (var room in client.rooms) {
        final participants = await room.getParticipants();

        // If the room name matches the group room pattern and contains a timestamp
        if (room.name.contains("Grid:Group:")) {
          final roomNameParts = room.name.split(":");

          if (roomNameParts.length >= 4) {
            final expirationTimestamp = int.tryParse(roomNameParts[2]) ?? 0;

            // Check if the room has expired
            if (expirationTimestamp > 0 && expirationTimestamp < now) {
              await room.leave();
              print('Left expired room: ${room.name} (${room.id})');
            }
          }
        } else if (participants.length == 1 && participants.first.id == client.userID && participants.first.membership == Membership.join) {
          // Leave the room if you're the only participant left
          await room.leave();
          print('Left room: ${room.name} (${room.id}) because you were the only participant left.');
        }
      }
    } catch (e) {
      print("Error cleaning rooms: $e");
    }
  }

  Future<void> createGroup(String groupName, List<String> userIds, int durationInHours) async {
    String? effectiveUserId = client.userID ?? client.userID?.localpart;
    if (effectiveUserId == null) {

      return;
    }

    // Calculate expiration timestamp
    int expirationTimestamp;
    if (durationInHours == 0) {
      // Infinite duration, set expiration to 0
      expirationTimestamp = 0;
    } else {
      // Calculate expiration time based on current time and duration
      final expirationTime = DateTime.now().add(Duration(hours: durationInHours));
      expirationTimestamp = expirationTime.millisecondsSinceEpoch ~/ 1000; // Convert to Unix timestamp
    }

    final roomName = "Grid:Group:$expirationTimestamp:$groupName:$effectiveUserId";
    try {
      // Create the room
      final roomId = await client.createRoom(
        name: roomName,
        isDirect: false,
        visibility: matrix_model.Visibility.private,
        initialState: [
          StateEvent(
            type: EventTypes.Encryption,
            content: {"algorithm": "m.megolm.v1.aes-sha2"},
          ),
        ],
      );
      // Invite users to the room
      for (String id in userIds) {
        if (id != effectiveUserId) {
          final fullUsername = '@' + id + ':' + client.homeserver.toString().replaceFirst('https://', '');
          await client.inviteUser(roomId, fullUsername);
        }
      }
      // Add the "Grid Group" tag to the room
      await client.setRoomTag(client.userID!, roomId, "Grid Group");
    } catch (e) {
      // Handle errors
      return;
    }
  }

  void sendLocationEvent(String roomId, bg.Location location) async {
    final room = client.getRoomById(roomId);
    if (room != null) {
      final latitude = location.coords.latitude;
      final longitude = location.coords.longitude;

      if (latitude != null && longitude != null) {
        // Create a unique hash for the location message
        final messageHash = '$latitude:$longitude';

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
          print("Location event sent to room $roomId: $latitude, $longitude");

          // Track the sent message
          _recentlySentMessages.putIfAbsent(roomId, () => {}).add(messageHash);

          // Trim history if needed
          if (_recentlySentMessages[roomId]!.length > _maxMessageHistory) {
            _recentlySentMessages[roomId]!.remove(_recentlySentMessages[roomId]!.first);
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

  Future<void> updateRooms(bg.Location location) async {
    List<Room> rooms = client.rooms; // Assuming `client.rooms` gives the list of rooms
    for (Room room in rooms) {
      // Get all joined members of the room
      var joinedMembers = room
          .getParticipants()
          .where((member) => member.membership == Membership.join)
          .toList();
      // Update groups
      if (joinedMembers.length > 2) {
        sendLocationEvent(room.id, location);
      }
      // Update contacts
      else if (joinedMembers.length == 2) {
        sendLocationEvent(room.id, location);
      }
      // TODO: check if approved keys to prevent sending
      // if keys have changed without user approval
      else {
        // Don't update
      }
    }
  }



  Map<String, Map<String, String>> getUserDeviceKeys(String userId) {
    final userDeviceKeys = client.userDeviceKeys[userId]?.deviceKeys.values;
    Map<String, Map<String, String>> deviceKeysMap = {};

    if (userDeviceKeys != null) {
      for (final deviceKeyEntry in userDeviceKeys) {
        final deviceId = deviceKeyEntry.deviceId;

        // Ensure deviceId is not null before proceeding
        if (deviceId != null) {
          // Collect all keys for this device, using an empty string if the key is null
          final deviceKeys = {
            "curve25519": deviceKeyEntry.keys['curve25519:$deviceId'] ?? "",
            "ed25519": deviceKeyEntry.keys['ed25519:$deviceId'] ?? ""
          };

          // Add this device's keys to the map with deviceId as the key
          deviceKeysMap[deviceId] = deviceKeys;
        }
      }
    }
    return deviceKeysMap; // Returns a map of device IDs to their key maps
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
      await client.sync();
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

            // Add this user to the direct users list and map them to the room.
            directUsers.add(otherMember);
            userRoomMap[otherMember] = room.id;
          } catch (e) {
            // Log if no other member is found.
            print('No other member found in room: ${room.id}');
            // TODO: may be causing issue with contacts screen
            await leaveRoom(room.id);
            print('Left room: ${room.id}');

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
