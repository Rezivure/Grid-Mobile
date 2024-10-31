import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:matrix/encryption/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/model.dart' as matrix_model;
import 'package:location/location.dart';  // Import LocationData
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';


enum RelationshipStatus {
  alreadyFriends,
  invitationSent,
  canInvite
}

class RoomProvider with ChangeNotifier {
  final Client client;
  final DatabaseService databaseService; // Add DatabaseService property
  String? _userId;
  final Encryption encryption;


  RoomProvider(this.client, this.databaseService) : encryption = Encryption(client: client)  {
    _loadUserId();
  }

  String? get userId => _userId;  // Public getter for userId

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = client.userID;
    prefs.setString('userId', userId!);
  }

  Future<void> updateOwnUserID() async {
    final id = client.userID;
    _userId = id;
  }

  List<Room> get rooms => client.rooms;

  Future<RelationshipStatus> getRelationshipStatus(String userId) async {
    await client.sync();

    String? effectiveUserId = _userId;

    if (effectiveUserId == null) {
      // Handle the error appropriately
      return RelationshipStatus.canInvite;
    }

    for (var room in client.rooms) {
      final roomName1 = "Grid:Direct:$effectiveUserId:$userId";
      final roomName2 = "Grid:Direct:$userId:$effectiveUserId";

      if (room.name == roomName1 || room.name == roomName2) {
        final participants = await room.getParticipants();

        // Get the membership status of both users in the room
        User? userMember;
        User? ownMember;

        try {
          userMember = participants.firstWhere((user) => user.id == userId);
        } on StateError {
          userMember = null;
        }

        try {
          ownMember = participants.firstWhere((user) => user.id == client.userID);
        } on StateError {
          ownMember = null;
        }

        if (userMember != null && ownMember != null) {
          if (userMember.membership == Membership.join &&
              ownMember.membership == Membership.join) {
            return RelationshipStatus.alreadyFriends;
          } else if (userMember.membership == Membership.invite ||
              ownMember.membership == Membership.invite) {
            return RelationshipStatus.invitationSent;
          }
        }
      }
    }

    return RelationshipStatus.canInvite;
  }


  Future<void> createAndInviteUser(String username, BuildContext context) async {
    String? effectiveUserId = _userId;

    if (effectiveUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to retrieve your user ID.')),
      );
      return;
    }

    // Normalize and construct the user ID
    String normalizedUserId = username.trim().toLowerCase();
    String matrixUserId = normalizedUserId.startsWith('@')
        ? normalizedUserId
        : '@$normalizedUserId:${dotenv.env['HOMESERVER']}';
    String displayUsername = normalizedUserId.startsWith('@')
        ? normalizedUserId.substring(1).split(':').first
        : normalizedUserId;

    // Check if the user exists before proceeding
    try {
      bool userExists = await this.userExists(matrixUserId);
      if (!userExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The user $displayUsername does not exist.')),
        );
        return;
      }
    } catch (e) {
      print('Error checking if user exists: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking user existence: $e')),
      );
      return;
    }

    // Proceed with creating the room and inviting the user
    final roomName1 = "Grid:Direct:$effectiveUserId:$matrixUserId";
    final roomName2 = "Grid:Direct:$matrixUserId:$effectiveUserId";

    try {
      RelationshipStatus status = await getRelationshipStatus(matrixUserId);

      if (status == RelationshipStatus.alreadyFriends) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You are already friends with $displayUsername.')),
        );
        return;
      } else if (status == RelationshipStatus.invitationSent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An invitation has already been sent to $displayUsername.')),
        );
        return;
      }

      final roomExists = client.rooms.any((room) =>
      room.name == roomName1 || room.name == roomName2);

      if (roomExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You already have a request or active session with $displayUsername.')),
        );
        return;
      }

      final roomId = await client.createRoom(
        name: roomName1,
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

      Room? room = client.getRoomById(roomId);

      if (room != null) {
        await room.addToDirectChat(client.userID!);
        await addTag(roomId, 'direct');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation sent to $displayUsername.')),
      );
    } catch (e) {
      print('Error creating room or inviting user: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error inviting user: $e')),
      );
    }
  }



  Future<bool> userExists(String userId) async {
    try {
      final response = await client.getUserProfile(userId);
      return response != null;
    } catch (e) {
      print('Error checking user existence: $e');
      return false;
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

  Future<String> getLastSeenTime(User user) async {
    try {
      final locations = await databaseService.getUserLocationById(user.id); // Replace with actual database logic
      if (locations.isEmpty) return 'Offline';

      final lastTimestamp = locations.first['timestamp'];
      if (lastTimestamp == null) return 'Offline';

      // Ensure the timestamp is in correct ISO 8601 format
      String validTimestamp = lastTimestamp.endsWith('Z') ? lastTimestamp : lastTimestamp + 'Z';

      final now = DateTime.now().toUtc();
      final lastSeen = DateTime.parse(validTimestamp); // Parse the corrected timestamp

      Duration difference = now.difference(lastSeen);

      if (difference.inSeconds < 60) {
        return '${difference.inSeconds}s ago';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      print("Error fetching last seen time: $e");
      return 'Offline';
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

  Future<List<Map<String, String>>> getInvites() async {
    List<Map<String, String>> inviteRooms = [];

    try {
      await client.sync();

      List<Room> invitedRooms = client.rooms.where((room) => room.membership == Membership.invite).toList();

      for (var room in invitedRooms) {
        // TODO figure out why sometimes not showing up
        // in debug mode
        var members = await room.getParticipants();


        var inviter = members.firstWhere(
                (member) => member.id != client.userID,
                );

        if (inviter == null) {
          continue;
        }

        String type = "";
        if (members.length > 2) {
          type = "group";
        } else if (members.length == 2) {
          type = "direct";
        } else {
          type = "unknown";
        }

        var invite = {
          "type": type,
          "inviter": inviter.id,
          "roomId": room.id,
          "roomName": room.name ?? "Unnamed Room",
        };

        inviteRooms.add(invite);
      }

      if (inviteRooms.isEmpty) {
        print("No invites found");
      } else {
        print("Found ${inviteRooms.length} invites");
      }
    } catch (e) {
      print("Bad getParticipants for getting invites");
      print("Error fetching invites: $e");
    }

    return inviteRooms;
  }


  Future<void> cleanRooms() async {
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
        } else if (participants.length == 1 && participants.first.id == client.userID) {
          // Leave the room if you're the only participant left
          await room.leave();
          print('Left room: ${room.name} (${room.id}) because you were the only participant left.');
        }
      }
    } catch (e) {
      print("Error cleaning rooms: $e");
    }
  }

  Future<void> leaveGroup(Room room) async {
    try {
      await room.leave();
      // Update any necessary state or data after leaving the room
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to leave group: $e');
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

  Future<void> acceptInvitation(String roomId) async {
    try {
      await client.joinRoom(roomId);

      notifyListeners();
    } catch (e) {
      print("Error accepting invitation: $e");
    }
  }

  Future<bool> leaveRoom(String roomId) async {
    try {
      await client.leaveRoom(roomId);
      notifyListeners();
      return true;
    } catch (e) {
      print("Error leaving room: $e");
      return false;
    }
  }


  Future<void> declineInvitation(String roomId) async {
    try {
      await client.leaveRoom(roomId);
      notifyListeners();
    } catch (e) {
      print("Error declining invitation: $e");
    }
  }


  int getPowerLevelByUserId(Room room, String userId) {
    return room.getPowerLevelByUserId(userId);
  }

  Future<bool> checkUsernameAvailability(String username) async {
    try {
      var response = await http.post(
        Uri.parse('${dotenv.env['GAUTH_URL']}/username'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'phone_number': '+10000000000',
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error checking username availability: $e');
      return false;
    }
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
  Future<void> createGroup(String groupName, List<String> userIds, int durationInHours, BuildContext context) async {
    String? effectiveUserId = _userId ?? client.userID?.localpart;
    if (effectiveUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to retrieve user ID.')),
      );
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
      // Notify the user of success
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Group $groupName created successfully')),
      );
    } catch (e) {
      // Handle errors
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating group: $e')),
      );
    }
  }


  Future<bool> isUserInRoom(String roomId, String userId) async {
    Room? room = client.getRoomById(roomId);
    if (room != null) {
      var participants = room.getParticipants();
      return participants.any((user) => user.id == userId && user.membership == Membership.join);
    }
    return false;
  }

  Future<bool> isUserInvited(String roomId, String userId) async {
    Room? room = client.getRoomById(roomId);
    if (room != null) {
      var participants = room.getParticipants();
      return participants.any(
              (user) => user.id == userId && user.membership == Membership.invite);
    }
    return false;
  }


  Future<List<Event>> getDecryptedRoomEvents(String roomId) async {
    final response = await client.getRoomEvents(roomId, Direction.b);
    final events = response.chunk;
    final room = await client.getRoomById(roomId); // redundant? TODO
    List<Event> decryptedContents = [];

    for (final event in events) {
      final matrixEvent = await Event.fromMatrixEvent(event, room!);
      final decryptedEvent = await encryption.decryptRoomEvent(roomId, matrixEvent);
      if (decryptedEvent.senderId != client.userID) {
        decryptedContents.add(decryptedEvent);
      }
    }
    return decryptedContents;
  }


  void sendLocationEvent(String roomId, LocationData locationData) async {
    final room = client.getRoomById(roomId);
    if (room != null) {
      // Extract latitude and longitude from LocationData
      final latitude = locationData.latitude;
      final longitude = locationData.longitude;

      if (latitude != null && longitude != null) {
        final eventContent = {
          'msgtype': 'm.location',
          'body': 'Current location',
          'geo_uri': 'geo:$latitude,$longitude',
          'description': 'Current location',
          'timestamp': DateTime.now().toUtc().toIso8601String()
        };

        try {
          await room.sendEvent(eventContent);
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

  void updateRooms(LocationData position) {
    List<Room> rooms = client.rooms;
    var roomsUpdated = 0;
    for (Room room in rooms) {
      var joinedMembers = room
          .getParticipants()
          .where((member) => member.membership == Membership.join)
          .toList();

      if (joinedMembers.length >= 2) {
        sendLocationEvent(room.id, position);
        roomsUpdated += 1;

      }
    }
    print("Updated a total of $roomsUpdated rooms with my location: $position");
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

          // Print device_id and each key type for debugging
          print('Device ID: $deviceId');
          deviceKeys.forEach((keyType, key) {
            print('$keyType Key: $key');
          });

          // Add this device's keys to the map with deviceId as the key
          deviceKeysMap[deviceId] = deviceKeys;
        }
      }
    }
    return deviceKeysMap; // Returns a map of device IDs to their key maps
  }


  Future<void> fetchAndUpdateLocations() async {
    // TODO: check unjoined/invited rooms
    // currently only checks joined rooms
    await cleanRooms(); // leave rooms that are expired or empty
    Map<String, dynamic> usersLocationAndKeysMap = {};

    final rooms = client.rooms.where((room) => room.membership == Membership.join);
    for (Room unreadRoom in rooms) {
      final events = await getDecryptedRoomEvents(unreadRoom.id);

      if (events.isNotEmpty) {
        final eventLocations = await processRoomEvents(events);
        eventLocations.forEach((userId, locationData) {
          var userDeviceKeys = getUserDeviceKeys(userId);
          var userLocationAndKeys = {
            ...locationData,
            'devices': userDeviceKeys, // Add all device keys for this user
          };
          usersLocationAndKeysMap[userId] = userLocationAndKeys;
        });
      }
    }
    await updateUserLocationsInDatabase(usersLocationAndKeysMap);
    print("Emitting updates after fully updating database.");
    databaseService.emitUpdatesToAppAfterUpdatingDB(); // Update ONCE after completed fetching
  }

  processRoomEvents(List<Event> events) async {
    // cleans up so only one location per room is grabbed
    Map<String, dynamic> userLocationMap = {};

    for (final event in events) {
      if (event.content['msgtype'] == 'm.location') {
        final String sender = event.senderId;
        final String geoUri = event.content['geo_uri'] as String;
        final String timestamp = event.content['timestamp'] as String;

        // Extract latitude and longitude from the geo_uri
        final latLong = geoUri.replaceFirst('geo:', '').split(',');
        final double latitude = double.parse(latLong[0]);
        final double longitude = double.parse(latLong[1]);

        // Check if we already have a record for this user and compare timestamps
        if (userLocationMap.containsKey(sender)) {
          final existingTimestamp = DateTime.parse(userLocationMap[sender]!['timestamp']);
          final newTimestamp = DateTime.parse(timestamp);
          if (newTimestamp.isAfter(existingTimestamp)) {
            // Update with the most recent event
            userLocationMap[sender] = {
              'latitude': latitude,
              'longitude': longitude,
              'timestamp': timestamp,
            };
          }
        } else {
          // If there's no other recent event, add the current event
          userLocationMap[sender] = {
            'latitude': latitude,
            'longitude': longitude,
            'timestamp': timestamp,
          };
        }
      }
    }

    return userLocationMap;
  }

  Future<void> updateUserLocationsInDatabase(Map<String, dynamic> eventLocations) async {
    for (final eventLocation in eventLocations.entries) {
      final userId = eventLocation.key;
      if (userId != null) {
        final latitude = eventLocation.value['latitude'] as double;
        final longitude = eventLocation.value['longitude'] as double;
        final timestamp = eventLocation.value['timestamp'] as String;
        final deviceKeys = eventLocation.value['devices'];

        // Encode device keys as JSON
        final deviceKeysJson = jsonEncode(deviceKeys);

        // Check if the userId already exists in the database
        final existing = await databaseService.getUserLocationById(userId);
        final hasNewKeys = await userHasNewDeviceKeys(userId, deviceKeys);

        if (existing.isEmpty) {
          // If no existing record, insert a new one
          await databaseService.insertUserLocation(
              userId, latitude, longitude, timestamp, deviceKeysJson
          );
        } else {
          // If the record exists, update it
          // first check if device keys changed
          if (hasNewKeys) {
            // TODO: implement a notification or update a new table
            // that keys have changed
          }
          await databaseService.updateUserLocation(
              userId, latitude, longitude, timestamp, deviceKeysJson
          );
        }
      }
    }
  }

  Future<bool> userHasNewDeviceKeys(String userId, Map<String, dynamic> newKeys) async {
    final curKeys = await databaseService.getDeviceKeysByUserId(userId);

    print(curKeys);
    if (curKeys == null) {
      return false; // actually return false since we don't need to alert
    }

    for (final key in newKeys.keys) {
      print(key);
      if (!curKeys.containsKey(key)) {
        return true; // New key found
      }
    }

    // All keys in newKeys are already present in curKeys
    return false;
  }

// end
}
