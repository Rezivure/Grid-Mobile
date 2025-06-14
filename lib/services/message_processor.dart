import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/utilities/message_parser.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:matrix/encryption/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/services/others_profile_service.dart';
import 'package:grid_frontend/services/logger_service.dart';

class MessageProcessor {
  static const String _tag = 'MessageProcessor';
  
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
      Logger.warning(_tag, 'Room not found for event', data: {'eventId': matrixEvent.eventId});
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
      } else if (msgtype == 'grid.group.avatar.announce') {
        // Handle group avatar announcement
        await _handleGroupAvatarAnnouncement(roomId, decryptedEvent.senderId, decryptedEvent.content);
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
      Logger.warning(_tag, 'Invalid message sender or timestamp');
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
      Logger.debug(_tag, 'Location saved', data: {'userId': sender});
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
      Logger.error(_tag, 'Failed to handle profile announcement: $e');
    }
  }
  
  /// Handle group avatar announcement message
  Future<void> _handleGroupAvatarAnnouncement(String roomId, String senderId, Map<String, dynamic> content) async {
    try {
      Logger.debug(_tag, 'Handling group avatar announcement', data: {
      'roomId': roomId,
      'senderId': senderId
    });
      // Verify sender has permission to change group avatar (power level >= 50)
      final room = client.getRoomById(roomId);
      if (room == null) {
        Logger.warning(_tag, 'Room not found for group avatar announcement');
        return;
      }
      
      final senderPowerLevel = room.getPowerLevelByUserId(senderId);
      Logger.debug(_tag, 'Sender power level', data: {'level': senderPowerLevel});
      if (senderPowerLevel < 50) {
        Logger.warning(_tag, 'Insufficient permissions for group avatar change');
        return;
      }
      
      final avatar = content['avatar'] as Map<String, dynamic>?;
      if (avatar != null) {
        Logger.debug(_tag, 'Processing group avatar data');
        await _othersProfileService.processGroupAvatarAnnouncement(roomId, avatar);
      } else {
        Logger.warning(_tag, 'No avatar data in content');
      }
    } catch (e) {
      Logger.error(_tag, 'Failed to handle group avatar announcement: $e');
    }
  }
}
