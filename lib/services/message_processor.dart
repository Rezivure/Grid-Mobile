import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/location_history_repository.dart';
import 'package:grid_frontend/repositories/room_location_history_repository.dart';
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
import 'package:grid_frontend/services/map_icon_sync_service.dart';
import 'package:grid_frontend/services/avatar_announcement_service.dart';

/// Callback type for decryption errors
typedef DecryptionErrorCallback = void Function(String senderId, String roomId);

class MessageProcessor {
  final Client client;
  final LocationRepository locationRepository;
  final LocationHistoryRepository locationHistoryRepository;
  final RoomLocationHistoryRepository? roomLocationHistoryRepository;
  final MessageParser messageParser;
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();
  final AvatarBloc? avatarBloc;
  final MapIconSyncService? mapIconSyncService;

  /// Callback for when decryption fails
  DecryptionErrorCallback? _onDecryptionError;

  MessageProcessor(
      this.locationRepository,
      this.locationHistoryRepository,
      this.messageParser,
      this.client,
      {this.avatarBloc,
      this.mapIconSyncService,
      this.roomLocationHistoryRepository}
      );

  /// Use the client's encryption instance which has the actual keys
  Encryption? get encryption => client.encryption;

  /// Set a callback to be notified of decryption errors
  void setDecryptionErrorCallback(DecryptionErrorCallback callback) {
    _onDecryptionError = callback;
  }

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
    final Event finalEvent = await Event.fromMatrixEvent(matrixEvent, room);

    // Use the client's encryption instance which has the actual decryption keys
    final enc = encryption;
    if (enc == null) {
      print('[MessageProcessor] Encryption not available, cannot decrypt');
      return null;
    }
    final Event decryptedEvent = await enc.decryptRoomEvent(finalEvent);

    // Check for decryption failure
    if (decryptedEvent.type == 'm.room.encrypted' &&
        decryptedEvent.content['msgtype'] == 'm.bad.encrypted') {
      print('[MessageProcessor] ⚠️ DECRYPTION FAILED for event from ${finalEvent.senderId}');
      _onDecryptionError?.call(finalEvent.senderId ?? 'unknown', roomId);
    }

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
      final msgType = decryptedEvent.content['msgtype'] as String?;
      print('[Message Processing] Processing message type: $msgType from ${decryptedEvent.senderId}');
      
      if (msgType == 'm.avatar.announcement') {
        await _handleAvatarAnnouncement(messageData);
      } else if (msgType == 'm.group.avatar.announcement') {
        await _handleGroupAvatarAnnouncement(messageData, roomId);
      } else if (msgType == 'm.avatar.state') {
        await _handleAvatarState(messageData);
      } else if (msgType == 'm.avatar.request') {
        await _handleAvatarRequest(messageData, roomId);
      } else if (_isMapIconEvent(msgType)) {
        // Handle map icon events
        await _handleMapIconEvent(roomId, messageData);
      } else if (msgType == 'm.location') {
        print('[Message Processing] Processing location message from ${decryptedEvent.senderId}');
        // Attempt to parse location message
        await _handleLocationMessageIfAny(messageData, roomId);
      } else {
        // Not a special message type we handle
      }
      return messageData;
    }
    // Not a message, return null
    return null;
  }


  /// Handle location message if it's detected
  Future<void> _handleLocationMessageIfAny(Map<String, dynamic> messageData, String roomId) async {
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
      print('[Location Processing] Found location message from $sender at ${locationData['latitude']}, ${locationData['longitude']}');
      final userLocation = UserLocation(
        userId: sender,
        latitude: locationData['latitude']!,
        longitude: locationData['longitude']!,
        timestamp: timestamp,
        iv: '', // IV is generated or handled in the repository
      );

      await locationRepository.insertLocation(userLocation);
      print('[Location Processing] Location saved for user: $sender');
      var confirm = await locationRepository.getLatestLocation(sender);
      
      // Save to room-specific location history
      if (roomLocationHistoryRepository != null) {
        await roomLocationHistoryRepository!.addLocationPoint(
          roomId: roomId,
          userId: sender,
          latitude: locationData['latitude']!,
          longitude: locationData['longitude']!,
        );
        print('Room location history saved for user: $sender in room: $roomId');
      }
      
      // Also save to legacy global history (can be deprecated later)
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

  /// Handle avatar state bundle messages
  Future<void> _handleAvatarState(Map<String, dynamic> messageData) async {
    try {
      final sender = messageData['sender'] as String?;
      final content = messageData['content'] as Map<String, dynamic>?;
      
      if (sender == null || content == null) {
        print('[Avatar State] Invalid avatar state - missing sender or content');
        return;
      }

      // Check if this state update is targeted to us
      final targetUser = content['target_user'] as String?;
      if (targetUser != null && targetUser != client.userID) {
        print('[Avatar State] State not targeted to this user, ignoring');
        return;
      }

      final avatarsList = content['avatars'] as List<dynamic>?;
      if (avatarsList == null || avatarsList.isEmpty) {
        print('[Avatar State] No avatars in state bundle');
        return;
      }

      print('[Avatar State] Processing avatar state bundle with ${avatarsList.length} avatars from $sender');

      // Process each avatar in the state
      for (final avatarData in avatarsList) {
        try {
          final userId = avatarData['user_id'] as String?;
          final avatarUrl = avatarData['avatar_url'] as String?;
          final encryption = avatarData['encryption'] as Map<String, dynamic>?;
          
          if (userId == null || avatarUrl == null || encryption == null) {
            continue; // Skip invalid entries
          }

          final key = encryption['key'] as String?;
          final iv = encryption['iv'] as String?;
          
          if (key == null || iv == null) {
            continue; // Skip entries without encryption data
          }

          print('[Avatar State] Processing avatar for user $userId');

          // Use AvatarBloc if available
          if (avatarBloc != null) {
            avatarBloc!.add(AvatarUpdateReceived(
              userId: userId,
              avatarUrl: avatarUrl,
              encryptionKey: key,
              encryptionIv: iv,
              isMatrixUrl: avatarUrl.startsWith('mxc://'),
            ));
          } else {
            // Fallback: Store avatar data directly
            final avatarDataToStore = {
              'uri': avatarUrl,
              'key': key,
              'iv': iv,
            };
            
            await secureStorage.write(
              key: 'avatar_$userId',
              value: json.encode(avatarDataToStore),
            );
            
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('avatar_is_matrix_$userId', avatarUrl.startsWith('mxc://'));
          }
        } catch (e) {
          print('[Avatar State] Error processing avatar in state: $e');
          continue; // Continue with other avatars
        }
      }
      
      print('[Avatar State] Finished processing ${avatarsList.length} avatars from state bundle');
    } catch (e) {
      print('[Avatar State] Error handling avatar state: $e');
    }
  }

  /// Handle avatar request messages
  Future<void> _handleAvatarRequest(Map<String, dynamic> messageData, String roomId) async {
    try {
      final sender = messageData['sender'] as String?;
      final content = messageData['content'] as Map<String, dynamic>?;
      
      if (sender == null || content == null) {
        print('[Avatar Request] Invalid request - missing sender or content');
        return;
      }

      // Don't respond to our own requests
      if (sender == client.userID) {
        return;
      }

      final requestedUsers = content['requested_users'] as List<dynamic>?;
      
      print('[Avatar Request] Received avatar request from $sender for users: ${requestedUsers?.join(", ") ?? "all"}');
      
      // Use the avatar service to handle the request
      final avatarService = AvatarAnnouncementService(client);
      await avatarService.handleAvatarRequest(roomId, sender, requestedUsers?.cast<String>());
      
    } catch (e) {
      print('[Avatar Request] Error handling avatar request: $e');
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
        encryptedData = file.data;
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
        encryptedData = file.data;
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
  
  /// Checks if a message type is a map icon event
  bool _isMapIconEvent(String? msgType) {
    if (msgType == null) return false;
    return msgType == MapIconSyncService.eventTypeCreate ||
           msgType == MapIconSyncService.eventTypeUpdate ||
           msgType == MapIconSyncService.eventTypeDelete ||
           msgType == MapIconSyncService.eventTypeState;
  }
  
  /// Handles map icon events
  Future<void> _handleMapIconEvent(String roomId, Map<String, dynamic> messageData) async {
    try {
      // Skip if we don't have the sync service
      if (mapIconSyncService == null) {
        print('[MapIcon] MapIconSyncService not available, skipping event');
        return;
      }
      
      final content = messageData['content'] as Map<String, dynamic>?;
      if (content == null) {
        print('[MapIcon] Invalid map icon event - missing content');
        return;
      }
      
      final senderId = messageData['sender'] as String?;
      
      // Don't process our own events (we already have them locally)
      if (senderId == client.userID) {
        print('[MapIcon] Skipping own map icon event');
        return;
      }
      
      // Process the icon event
      await mapIconSyncService!.processIconEvent(roomId, content);
      
      print('[MapIcon] Processed map icon event of type: ${content['msgtype']}');
    } catch (e) {
      print('[MapIcon] Error handling map icon event: $e');
    }
  }
}
