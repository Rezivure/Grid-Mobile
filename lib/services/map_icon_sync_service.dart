import 'dart:async';
import 'dart:convert';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/models/map_icon.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/blocs/map_icons/map_icons_bloc.dart';
import 'package:grid_frontend/blocs/map_icons/map_icons_event.dart';

/// Service responsible for synchronizing map icons across all room members
/// Handles sending, receiving, and maintaining consistency of map icons
class MapIconSyncService {
  final Client client;
  final MapIconRepository _mapIconRepository;
  final MapIconsBloc? mapIconsBloc;
  
  // Rate limiting configuration
  static const int _maxIconsPerMinute = 10;
  static const Duration _rateLimitWindow = Duration(minutes: 1);
  
  // Deduplication tracking
  final Map<String, Set<String>> _recentlySentIcons = {};
  final Map<String, List<DateTime>> _rateLimitTracker = {};
  
  // Event type constants
  static const String eventTypeCreate = 'm.map.icon.create';
  static const String eventTypeUpdate = 'm.map.icon.update';
  static const String eventTypeDelete = 'm.map.icon.delete';
  static const String eventTypeState = 'm.map.icon.state';
  
  MapIconSyncService({
    required this.client,
    MapIconRepository? mapIconRepository,
    this.mapIconsBloc,
  }) : _mapIconRepository = mapIconRepository ?? MapIconRepository(DatabaseService());
  
  /// Sends a create icon event to the room
  Future<bool> sendIconCreate(String roomId, MapIcon icon) async {
    try {
      // Check rate limit
      if (!_checkRateLimit(roomId)) {
        print('[MapIconSync] Rate limit exceeded for room $roomId');
        return false;
      }
      
      // Check for duplicate
      final messageHash = _generateIconHash(icon);
      if (_isDuplicate(roomId, messageHash)) {
        print('[MapIconSync] Duplicate icon message detected, skipping');
        return false;
      }
      
      final room = client.getRoomById(roomId);
      if (room == null) {
        print('[MapIconSync] Room $roomId not found');
        return false;
      }
      
      final eventContent = {
        'msgtype': eventTypeCreate,
        'icon_id': icon.id,
        'latitude': icon.latitude,
        'longitude': icon.longitude,
        'icon_type': icon.iconType,
        'icon_data': icon.iconData,
        'name': icon.name,
        'description': icon.description,
        'creator_id': icon.creatorId,
        'created_at': icon.createdAt.toIso8601String(),
        'expires_at': icon.expiresAt?.toIso8601String(),
        'metadata': icon.metadata,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      
      await room.sendEvent(eventContent);
      
      // Track sent message
      _trackSentIcon(roomId, messageHash);
      _updateRateLimit(roomId);
      
      print('[MapIconSync] Icon create event sent for ${icon.id}');
      return true;
    } catch (e) {
      print('[MapIconSync] Error sending icon create event: $e');
      return false;
    }
  }
  
  /// Sends an update icon event to the room
  Future<bool> sendIconUpdate(String roomId, MapIcon icon) async {
    try {
      // Check if user is the creator
      if (icon.creatorId != client.userID) {
        print('[MapIconSync] User is not the creator of icon ${icon.id}');
        return false;
      }
      
      // Check rate limit
      if (!_checkRateLimit(roomId)) {
        print('[MapIconSync] Rate limit exceeded for room $roomId');
        return false;
      }
      
      final room = client.getRoomById(roomId);
      if (room == null) {
        print('[MapIconSync] Room $roomId not found');
        return false;
      }
      
      final eventContent = {
        'msgtype': eventTypeUpdate,
        'icon_id': icon.id,
        'latitude': icon.latitude,
        'longitude': icon.longitude,
        'icon_type': icon.iconType,
        'icon_data': icon.iconData,
        'name': icon.name,
        'description': icon.description,
        'expires_at': icon.expiresAt?.toIso8601String(),
        'metadata': icon.metadata,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      
      await room.sendEvent(eventContent);
      
      _updateRateLimit(roomId);
      
      print('[MapIconSync] Icon update event sent for ${icon.id}');
      return true;
    } catch (e) {
      print('[MapIconSync] Error sending icon update event: $e');
      return false;
    }
  }
  
  /// Sends a delete icon event to the room
  Future<bool> sendIconDelete(String roomId, String iconId, String creatorId) async {
    try {
      // Check if user is the creator
      if (creatorId != client.userID) {
        print('[MapIconSync] User is not the creator of icon $iconId');
        return false;
      }
      
      // Check rate limit
      if (!_checkRateLimit(roomId)) {
        print('[MapIconSync] Rate limit exceeded for room $roomId');
        return false;
      }
      
      final room = client.getRoomById(roomId);
      if (room == null) {
        print('[MapIconSync] Room $roomId not found');
        return false;
      }
      
      final eventContent = {
        'msgtype': eventTypeDelete,
        'icon_id': iconId,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      
      await room.sendEvent(eventContent);
      
      _updateRateLimit(roomId);
      
      print('[MapIconSync] Icon delete event sent for $iconId');
      return true;
    } catch (e) {
      print('[MapIconSync] Error sending icon delete event: $e');
      return false;
    }
  }
  
  /// Sends all current icons to new room members
  Future<bool> sendIconState(String roomId, {String? targetUserId}) async {
    try {
      final room = client.getRoomById(roomId);
      if (room == null) {
        print('[MapIconSync] Room $roomId not found');
        return false;
      }
      
      // Get all icons for this room
      final icons = await _mapIconRepository.getIconsForRoom(roomId);
      
      if (icons.isEmpty) {
        print('[MapIconSync] No icons to share for room $roomId');
        return true;
      }
      
      // Convert icons to event format
      final iconData = icons.map((icon) => {
        'icon_id': icon.id,
        'latitude': icon.latitude,
        'longitude': icon.longitude,
        'icon_type': icon.iconType,
        'icon_data': icon.iconData,
        'name': icon.name,
        'description': icon.description,
        'creator_id': icon.creatorId,
        'created_at': icon.createdAt.toIso8601String(),
        'expires_at': icon.expiresAt?.toIso8601String(),
        'metadata': icon.metadata,
      }).toList();
      
      final eventContent = {
        'msgtype': eventTypeState,
        'icons': iconData,
        'target_user': targetUserId, // Optional: specify recipient
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      
      await room.sendEvent(eventContent);
      
      print('[MapIconSync] Icon state sent with ${icons.length} icons to room $roomId');
      return true;
    } catch (e) {
      print('[MapIconSync] Error sending icon state: $e');
      return false;
    }
  }
  
  /// Processes incoming icon events from other users
  Future<void> processIconEvent(String roomId, Map<String, dynamic> event) async {
    try {
      final msgType = event['msgtype'];
      
      switch (msgType) {
        case eventTypeCreate:
          await _handleIconCreate(roomId, event);
          break;
        case eventTypeUpdate:
          await _handleIconUpdate(roomId, event);
          break;
        case eventTypeDelete:
          await _handleIconDelete(roomId, event);
          break;
        case eventTypeState:
          await _handleIconState(roomId, event);
          break;
        default:
          print('[MapIconSync] Unknown icon event type: $msgType');
      }
    } catch (e) {
      print('[MapIconSync] Error processing icon event: $e');
    }
  }
  
  /// Handles incoming icon create events
  Future<void> _handleIconCreate(String roomId, Map<String, dynamic> event) async {
    try {
      final iconId = event['icon_id'] as String?;
      if (iconId == null) {
        print('[MapIconSync] Icon create event missing icon_id');
        return;
      }
      
      // Check if icon already exists
      final existingIcons = await _mapIconRepository.getIconsForRoom(roomId);
      if (existingIcons.any((icon) => icon.id == iconId)) {
        print('[MapIconSync] Icon $iconId already exists, skipping create');
        return;
      }
      
      // Create MapIcon from event
      final icon = MapIcon(
        id: iconId,
        roomId: roomId,
        creatorId: event['creator_id'] ?? 'unknown',
        latitude: (event['latitude'] as num).toDouble(),
        longitude: (event['longitude'] as num).toDouble(),
        iconType: event['icon_type'] ?? 'icon',
        iconData: event['icon_data'] ?? 'pin',
        name: event['name'],
        description: event['description'],
        createdAt: event['created_at'] != null 
          ? DateTime.parse(event['created_at'])
          : DateTime.now(),
        expiresAt: event['expires_at'] != null
          ? DateTime.parse(event['expires_at'])
          : null,
        metadata: event['metadata'],
      );
      
      // Save to local database
      await _mapIconRepository.insertMapIcon(icon);
      
      // Notify the BLoC about the new icon
      mapIconsBloc?.add(MapIconCreated(icon));
      
      print('[MapIconSync] Icon $iconId created from remote event');
    } catch (e) {
      print('[MapIconSync] Error handling icon create: $e');
    }
  }
  
  /// Handles incoming icon update events
  Future<void> _handleIconUpdate(String roomId, Map<String, dynamic> event) async {
    try {
      final iconId = event['icon_id'] as String?;
      if (iconId == null) {
        print('[MapIconSync] Icon update event missing icon_id');
        return;
      }
      
      // Get existing icon
      final existingIcons = await _mapIconRepository.getIconsForRoom(roomId);
      final existingIcon = existingIcons.firstWhere(
        (icon) => icon.id == iconId,
        orElse: () => throw Exception('Icon not found'),
      );
      
      // Create updated icon
      final updatedIcon = MapIcon(
        id: iconId,
        roomId: roomId,
        creatorId: existingIcon.creatorId, // Keep original creator
        latitude: event['latitude'] != null 
          ? (event['latitude'] as num).toDouble()
          : existingIcon.latitude,
        longitude: event['longitude'] != null
          ? (event['longitude'] as num).toDouble()
          : existingIcon.longitude,
        iconType: event['icon_type'] ?? existingIcon.iconType,
        iconData: event['icon_data'] ?? existingIcon.iconData,
        name: event['name'] ?? existingIcon.name,
        description: event['description'],
        createdAt: existingIcon.createdAt, // Keep original creation time
        expiresAt: event['expires_at'] != null
          ? DateTime.parse(event['expires_at'])
          : existingIcon.expiresAt,
        metadata: event['metadata'] ?? existingIcon.metadata,
      );
      
      // Update in local database
      await _mapIconRepository.updateMapIcon(updatedIcon);
      
      // Notify the BLoC about the updated icon
      mapIconsBloc?.add(MapIconUpdated(updatedIcon));
      
      print('[MapIconSync] Icon $iconId updated from remote event');
    } catch (e) {
      print('[MapIconSync] Error handling icon update: $e');
    }
  }
  
  /// Handles incoming icon delete events
  Future<void> _handleIconDelete(String roomId, Map<String, dynamic> event) async {
    try {
      final iconId = event['icon_id'] as String?;
      if (iconId == null) {
        print('[MapIconSync] Icon delete event missing icon_id');
        return;
      }
      
      // Delete from local database
      await _mapIconRepository.deleteMapIcon(iconId);
      
      // Notify the BLoC about the deleted icon
      // We need to get the room ID from somewhere - let's get it from the existing icons
      final existingIcons = await _mapIconRepository.getActiveIcons();
      final deletedIcon = existingIcons.firstWhere(
        (icon) => icon.id == iconId,
        orElse: () => MapIcon(
          id: iconId,
          roomId: '', // Will be handled by BLoC
          creatorId: '',
          latitude: 0,
          longitude: 0,
          iconType: '',
          iconData: '',
          name: null,
          description: null,
          createdAt: DateTime.now(),
          expiresAt: null,
          metadata: null,
        ),
      );
      
      mapIconsBloc?.add(MapIconDeleted(iconId: iconId, roomId: deletedIcon.roomId));
      
      print('[MapIconSync] Icon $iconId deleted from remote event');
    } catch (e) {
      print('[MapIconSync] Error handling icon delete: $e');
    }
  }
  
  /// Handles incoming icon state events (bulk update)
  Future<void> _handleIconState(String roomId, Map<String, dynamic> event) async {
    try {
      // Check if this state update is targeted to us
      final targetUser = event['target_user'] as String?;
      if (targetUser != null && targetUser != client.userID) {
        print('[MapIconSync] Icon state not targeted to this user, ignoring');
        return;
      }
      
      final iconsList = event['icons'] as List<dynamic>?;
      if (iconsList == null || iconsList.isEmpty) {
        print('[MapIconSync] Icon state event has no icons');
        return;
      }
      
      // Get existing icons to avoid duplicates
      final existingIcons = await _mapIconRepository.getIconsForRoom(roomId);
      final existingIconIds = existingIcons.map((icon) => icon.id).toSet();
      
      // Process each icon in the state
      for (final iconData in iconsList) {
        try {
          final iconId = iconData['icon_id'] as String?;
          if (iconId == null || existingIconIds.contains(iconId)) {
            continue; // Skip if no ID or already exists
          }
          
          final icon = MapIcon(
            id: iconId,
            roomId: roomId,
            creatorId: iconData['creator_id'] ?? 'unknown',
            latitude: (iconData['latitude'] as num).toDouble(),
            longitude: (iconData['longitude'] as num).toDouble(),
            iconType: iconData['icon_type'] ?? 'icon',
            iconData: iconData['icon_data'] ?? 'pin',
            name: iconData['name'],
            description: iconData['description'],
            createdAt: iconData['created_at'] != null
              ? DateTime.parse(iconData['created_at'])
              : DateTime.now(),
            expiresAt: iconData['expires_at'] != null
              ? DateTime.parse(iconData['expires_at'])
              : null,
            metadata: iconData['metadata'],
          );
          
          await _mapIconRepository.insertMapIcon(icon);
          print('[MapIconSync] Icon ${icon.id} added from state update');
        } catch (e) {
          print('[MapIconSync] Error processing icon in state: $e');
          continue; // Continue with other icons
        }
      }
      
      // Notify the BLoC about the bulk update
      final newIcons = <MapIcon>[];
      for (final iconData in iconsList) {
        try {
          final iconId = iconData['icon_id'] as String?;
          if (iconId == null || existingIconIds.contains(iconId)) {
            continue;
          }
          
          final icon = MapIcon(
            id: iconId,
            roomId: roomId,
            creatorId: iconData['creator_id'] ?? 'unknown',
            latitude: (iconData['latitude'] as num).toDouble(),
            longitude: (iconData['longitude'] as num).toDouble(),
            iconType: iconData['icon_type'] ?? 'icon',
            iconData: iconData['icon_data'] ?? 'pin',
            name: iconData['name'],
            description: iconData['description'],
            createdAt: iconData['created_at'] != null
              ? DateTime.parse(iconData['created_at'])
              : DateTime.now(),
            expiresAt: iconData['expires_at'] != null
              ? DateTime.parse(iconData['expires_at'])
              : null,
            metadata: iconData['metadata'],
          );
          
          newIcons.add(icon);
        } catch (e) {
          print('[MapIconSync] Error processing icon in state: $e');
          continue;
        }
      }
      
      if (newIcons.isNotEmpty) {
        mapIconsBloc?.add(MapIconsBulkUpdate(icons: newIcons, roomId: roomId));
      }
      
      print('[MapIconSync] Processed ${iconsList.length} icons from state update');
    } catch (e) {
      print('[MapIconSync] Error handling icon state: $e');
    }
  }
  
  /// Checks if an operation would exceed rate limit
  bool _checkRateLimit(String roomId) {
    final now = DateTime.now();
    final tracker = _rateLimitTracker[roomId] ?? [];
    
    // Remove old entries outside the window
    tracker.removeWhere((time) => 
      now.difference(time) > _rateLimitWindow
    );
    
    return tracker.length < _maxIconsPerMinute;
  }
  
  /// Updates rate limit tracking for a room
  void _updateRateLimit(String roomId) {
    _rateLimitTracker.putIfAbsent(roomId, () => []).add(DateTime.now());
  }
  
  /// Generates a hash for an icon to detect duplicates
  String _generateIconHash(MapIcon icon) {
    return '${icon.id}_${icon.latitude}_${icon.longitude}_${icon.iconData}';
  }
  
  /// Checks if an icon message is a duplicate
  bool _isDuplicate(String roomId, String messageHash) {
    final recentMessages = _recentlySentIcons[roomId] ?? {};
    return recentMessages.contains(messageHash);
  }
  
  /// Tracks a sent icon message for deduplication
  void _trackSentIcon(String roomId, String messageHash) {
    _recentlySentIcons.putIfAbsent(roomId, () => {}).add(messageHash);
    
    // Clean up old entries periodically (keep last 50)
    if (_recentlySentIcons[roomId]!.length > 50) {
      final messages = _recentlySentIcons[roomId]!.toList();
      _recentlySentIcons[roomId] = messages.skip(messages.length - 50).toSet();
    }
  }
  
  /// Clears rate limit and deduplication data for a room
  void clearRoomData(String roomId) {
    _recentlySentIcons.remove(roomId);
    _rateLimitTracker.remove(roomId);
  }
}