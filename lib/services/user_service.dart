import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:matrix/matrix.dart';
import 'package:collection/collection.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/models/grid_user.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:http/http.dart' as http;

enum RelationshipStatus {
  alreadyFriends,
  invitationSent,
  canInvite
}

class UserService {
  final Client client;
  final LocationRepository locationRepository;

  UserService(this.client, this.locationRepository);

  Future<bool> userExists(String userId) async {
    print("IN USER EXISTS");
    print(userId);
    try {
      print("Checking if $userId exists.");
      final response = await client.getUserProfile(userId);
      return response != null;
    } catch (e) {
      print('Error checking user existence: $e');
      return false;
    }
  }

  Future<String?> getMyUserId() async {
    return client.userID;
  }

  Future<RelationshipStatus> getRelationshipStatus(String effectiveUserId, String targetUserId) async {
    await client.sync();

    for (var room in client.rooms) {
      final roomName1 = "Grid:Direct:$effectiveUserId:$targetUserId";
      final roomName2 = "Grid:Direct:$targetUserId:$effectiveUserId";

      if (room.name == roomName1 || room.name == roomName2) {
        final participants = await room.getParticipants();

        final User? userMember = participants.firstWhereOrNull(
              (user) => user.id == targetUserId,
        );

        final User? ownMember = participants.firstWhereOrNull(
              (user) => user.id == client.userID,
        );

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

  Future<String> getLastSeenTime(String userId) async {
    try {
      final location = await locationRepository.getLatestLocationFromHistory(userId);
      if (location == null) return 'Offline';
      final lastTimestamp = location.timestamp;
      if (lastTimestamp == "null") return 'Offline';
      final lastSeen = DateTime.parse(lastTimestamp);
      return timeAgo(lastSeen); // Use the utility function
    } catch (e) {
      print("Error fetching last seen time for user $userId: $e");
      return 'Offline';
    }
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

}
