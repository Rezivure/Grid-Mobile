import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/utilities/message_parser.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:matrix/encryption/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/services/others_profile_service.dart';

class MessageProcessor {
  final Client client;
  final Encryption encryption;
  final LocationRepository locationRepository;
  final MessageParser messageParser;
  static final OthersProfileService _othersProfileService = OthersProfileService();

  MessageProcessor(
      this.locationRepository,
      this.messageParser,
      this.client,
      ) : encryption = Encryption(client: client);
      
  static OthersProfileService get othersProfileService => _othersProfileService;

  /// Process a single event from a room. Decrypt if necessary,
  /// then parse and store location messages if found.
  /// Returns a Map<String, dynamic> representing the message if it's a `m.room.message`,
  /// or null otherwise.
  Future<Map<String, dynamic>?> processEvent(String roomId, MatrixEvent matrixEvent) async {
    final room = client.getRoomById(roomId);
    if (room == null) {
      print("Room not found for event ${matrixEvent.eventId}");
      return null;
    }
    // Convert MatrixEvent to Event
    final Event finalEvent = await Event.fromMatrixEvent(matrixEvent, room);
    // Decrypt the event
    final Event decryptedEvent = await encryption.decryptRoomEvent(roomId, finalEvent);
    // Check if the decrypted event is now a message
    if (decryptedEvent.type == EventTypes.Message && decryptedEvent.content['msgtype'] != null) {
      // Skip message if originated from self
      if (decryptedEvent.senderId == client.userID) {
        return null;
      }
      final messageData = {
        'eventId': decryptedEvent.eventId,
        'sender': decryptedEvent.senderId,
        'content': decryptedEvent.content,
        'timestamp': decryptedEvent.originServerTs,
      };

      // Check message type
      final msgtype = decryptedEvent.content['msgtype'] as String?;
      
      if (msgtype == 'grid.profile.announce') {
        // Handle profile announcement
        await _handleProfileAnnouncement(decryptedEvent.senderId, decryptedEvent.content);
        // Don't return as a regular message
        return null;
      } else {
        // Attempt to parse location message
        await _handleLocationMessageIfAny(messageData);
        return messageData;
      }
    }
    // Not a message, return null
    return null;
  }


  /// Handle location message if it's detected
  Future<void> _handleLocationMessageIfAny(Map<String, dynamic> messageData) async {
    final sender = messageData['sender'] as String?;
    final rawTimestamp = messageData['timestamp'];
    final timestamp = rawTimestamp is DateTime
        ? rawTimestamp.toIso8601String()
        : rawTimestamp?.toString();

    if (sender == null || timestamp == null) {
      print('Invalid message sender or timestamp');
      return;
    }

    final locationData = messageParser.parseLocationMessage(messageData);
    if (locationData != null) {
      final userLocation = UserLocation(
        userId: sender,
        latitude: locationData['latitude']!,
        longitude: locationData['longitude']!,
        timestamp: timestamp,
        iv: '', // IV is generated or handled in the repository
      );

      await locationRepository.insertLocation(userLocation);
      print('Location saved for user: $sender');
      var confirm = await locationRepository.getLatestLocation(sender);
    } else {
      // It's a message, but not a location message
    }
  }
  
  /// Handle profile announcement message
  Future<void> _handleProfileAnnouncement(String senderId, Map<String, dynamic> content) async {
    try {
      final profile = content['profile'] as Map<String, dynamic>?;
      if (profile != null) {
        await _othersProfileService.processProfileAnnouncement(senderId, profile);
      }
    } catch (e) {
      print('Error handling profile announcement: $e');
    }
  }
}
