import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/location_history_repository.dart';
import 'package:grid_frontend/utilities/message_parser.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:matrix/encryption/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';
import 'dart:typed_data';
import 'package:grid_frontend/widgets/user_avatar.dart';
import 'package:grid_frontend/widgets/group_avatar.dart';
import 'package:grid_frontend/services/avatar_cache_service.dart';
import 'package:grid_frontend/blocs/avatar/avatar_bloc.dart';
import 'package:grid_frontend/blocs/avatar/avatar_event.dart';

class MessageProcessor {
  final Client client;
  final Encryption encryption;
  final LocationRepository locationRepository;
  final LocationHistoryRepository locationHistoryRepository;
  final MessageParser messageParser;
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();
  final AvatarBloc? avatarBloc;
  

  MessageProcessor(
      this.locationRepository,
      this.locationHistoryRepository,
      this.messageParser,
      this.client,
      {this.avatarBloc}
      ) : encryption = Encryption(client: client);

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

      // Check message type and handle accordingly
      final msgType = decryptedEvent.content['msgtype'];
      if (msgType == 'm.avatar.announcement') {
        await _handleAvatarAnnouncement(messageData);
      } else if (msgType == 'm.group.avatar.announcement') {
        await _handleGroupAvatarAnnouncement(messageData, roomId);
      } else {
        // Attempt to parse location message
        await _handleLocationMessageIfAny(messageData);
      }
      return messageData;
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
      
      // Also save to location history
      await locationHistoryRepository.addLocationPoint(sender, locationData['latitude']!, locationData['longitude']!);
    } else {
      // It's a message, but not a location message
    }
  }

  /// Handle avatar announcement messages
  Future<void> _handleAvatarAnnouncement(Map<String, dynamic> messageData) async {
    try {
      final sender = messageData['sender'] as String?;
      final content = messageData['content'] as Map<String, dynamic>?;
      
      if (sender == null || content == null) {
        print('[Avatar Processing] Invalid avatar announcement - missing sender or content');
        return;
      }

      final avatarUrl = content['avatar_url'] as String?;
      final encryption = content['encryption'] as Map<String, dynamic>?;
      
      if (avatarUrl == null || encryption == null) {
        print('[Avatar Processing] Invalid avatar announcement - missing avatar_url or encryption');
        return;
      }

      final key = encryption['key'] as String?;
      final iv = encryption['iv'] as String?;
      
      if (key == null || iv == null) {
        print('[Avatar Processing] Invalid avatar announcement - missing encryption key or iv');
        return;
      }

      print('[Avatar Processing] Processing avatar announcement from $sender');

      // Use AvatarBloc if available
      if (avatarBloc != null) {
        // Send avatar update event to bloc
        avatarBloc!.add(AvatarUpdateReceived(
          userId: sender,
          avatarUrl: avatarUrl,
          encryptionKey: key,
          encryptionIv: iv,
          isMatrixUrl: avatarUrl.startsWith('mxc://'),
        ));
      } else {
        // Fallback to old behavior if no bloc
        // Clear any existing avatar data for this user
        await secureStorage.delete(key: 'avatar_$sender');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('avatar_is_matrix_$sender');
        
        // Clear the avatar cache
        await UserAvatar.clearCache(sender);

        // Determine if it's a Matrix URL or R2 URL
        final isMatrixUrl = avatarUrl.startsWith('mxc://');

        // Store the new avatar data
        final avatarData = {
          'uri': avatarUrl,
          'key': key,
          'iv': iv,
        };
        
        await secureStorage.write(
          key: 'avatar_$sender',
          value: json.encode(avatarData),
        );
        
        // Store whether it's a Matrix avatar
        await prefs.setBool('avatar_is_matrix_$sender', isMatrixUrl);
        
        print('[Avatar Processing] Stored avatar data for $sender (isMatrix: $isMatrixUrl)');
        
        // Download and cache the avatar immediately
        await _downloadAndCacheAvatar(sender, avatarUrl, key, iv, isMatrixUrl);
      }
      
    } catch (e) {
      print('[Avatar Processing] Error handling avatar announcement: $e');
    }
  }

  /// Handle group avatar announcement messages
  Future<void> _handleGroupAvatarAnnouncement(Map<String, dynamic> messageData, String roomId) async {
    try {
      final content = messageData['content'] as Map<String, dynamic>?;
      
      if (content == null) {
        print('[Group Avatar Processing] Invalid group avatar announcement - missing content');
        return;
      }

      final avatarUrl = content['avatar_url'] as String?;
      final encryption = content['encryption'] as Map<String, dynamic>?;
      
      if (avatarUrl == null || encryption == null) {
        print('[Group Avatar Processing] Invalid group avatar announcement - missing avatar_url or encryption');
        return;
      }

      final key = encryption['key'] as String?;
      final iv = encryption['iv'] as String?;
      
      if (key == null || iv == null) {
        print('[Group Avatar Processing] Invalid group avatar announcement - missing encryption key or iv');
        return;
      }

      print('[Group Avatar Processing] Processing group avatar announcement for room $roomId');

      // Use AvatarBloc if available
      if (avatarBloc != null) {
        // Send group avatar update event to bloc
        avatarBloc!.add(GroupAvatarUpdateReceived(
          roomId: roomId,
          avatarUrl: avatarUrl,
          encryptionKey: key,
          encryptionIv: iv,
          isMatrixUrl: avatarUrl.startsWith('mxc://'),
        ));
      } else {
        // Fallback to old behavior if no bloc
        // Clear any existing avatar data for this group
        await secureStorage.delete(key: 'group_avatar_$roomId');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('group_avatar_is_matrix_$roomId');
        
        // Clear the avatar cache
        await GroupAvatar.clearCache(roomId);

        // Determine if it's a Matrix URL or R2 URL
        final isMatrixUrl = avatarUrl.startsWith('mxc://');

        // Store the new avatar data
        final avatarData = {
          'uri': avatarUrl,
          'key': key,
          'iv': iv,
        };
        
        await secureStorage.write(
          key: 'group_avatar_$roomId',
          value: json.encode(avatarData),
        );
        
        // Store whether it's a Matrix avatar
        await prefs.setBool('group_avatar_is_matrix_$roomId', isMatrixUrl);
        
        print('[Group Avatar Processing] Stored group avatar data for room $roomId (isMatrix: $isMatrixUrl)');
      }
      
    } catch (e) {
      print('[Group Avatar Processing] Error handling group avatar announcement: $e');
    }
  }

  /// Download and cache group avatar for immediate display
  Future<void> _downloadAndCacheGroupAvatar(String roomId, String avatarUrl, String keyBase64, String ivBase64, bool isMatrix) async {
    try {
      print('[Group Avatar Processing] Pre-downloading group avatar for room $roomId');
      
      Uint8List encryptedData;
      
      if (isMatrix) {
        // Download from Matrix
        final mxcUri = Uri.parse(avatarUrl);
        final serverName = mxcUri.host;
        final mediaId = mxcUri.path.substring(1);
        
        final file = await client.getContent(serverName, mediaId);
        encryptedData = Uint8List.fromList(file.data);
      } else {
        // Download from R2
        final response = await http.get(Uri.parse(avatarUrl));
        if (response.statusCode != 200) {
          print('[Group Avatar Processing] Failed to download avatar from R2: ${response.statusCode}');
          return;
        }
        encryptedData = response.bodyBytes;
      }
      
      // Decrypt the avatar
      final key = encrypt.Key.fromBase64(keyBase64);
      final iv = encrypt.IV.fromBase64(ivBase64);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypt.Encrypted(encryptedData);
      final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
      
      // Store in the persistent cache
      final avatarBytes = Uint8List.fromList(decrypted);
      // Note: GroupAvatar should have its own cache service similar to UserAvatar
      // For now, just notify the update
      
      print('[Group Avatar Processing] Successfully downloaded and decrypted group avatar for room $roomId');
      
      // Note: Group avatar notification should be handled through AvatarBloc
      
    } catch (e) {
      print('[Group Avatar Processing] Error pre-downloading group avatar: $e');
    }
  }

  /// Download and cache avatar for immediate display
  Future<void> _downloadAndCacheAvatar(String userId, String avatarUrl, String keyBase64, String ivBase64, bool isMatrix) async {
    try {
      print('[Avatar Processing] Pre-downloading avatar for $userId');
      
      Uint8List encryptedData;
      
      if (isMatrix) {
        // Download from Matrix
        final mxcUri = Uri.parse(avatarUrl);
        final serverName = mxcUri.host;
        final mediaId = mxcUri.path.substring(1);
        
        final file = await client.getContent(serverName, mediaId);
        encryptedData = Uint8List.fromList(file.data);
      } else {
        // Download from R2
        final response = await http.get(Uri.parse(avatarUrl));
        if (response.statusCode != 200) {
          print('[Avatar Processing] Failed to download avatar from R2: ${response.statusCode}');
          return;
        }
        encryptedData = response.bodyBytes;
      }
      
      // Decrypt the avatar
      final key = encrypt.Key.fromBase64(keyBase64);
      final iv = encrypt.IV.fromBase64(ivBase64);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypt.Encrypted(encryptedData);
      final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
      
      // Store in the persistent cache
      final avatarBytes = Uint8List.fromList(decrypted);
      final AvatarCacheService cacheService = AvatarCacheService();
      await cacheService.initialize();
      await cacheService.put(userId, avatarBytes);
      
      print('[Avatar Processing] Successfully downloaded and decrypted avatar for $userId');
      
      // Notify all UserAvatar widgets to refresh for this user
      UserAvatar.notifyAvatarUpdated(userId);
      
    } catch (e) {
      print('[Avatar Processing] Error pre-downloading avatar: $e');
    }
  }
}
