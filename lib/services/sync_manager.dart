import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/services/message_processor.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/models/room.dart' as GridRoom;
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/models/grid_user.dart' as GridUser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/services/avatar_announcement_service.dart';
import 'package:grid_frontend/services/map_icon_sync_service.dart';

import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/services/location_manager.dart';


import '../blocs/groups/groups_bloc.dart';
import '../blocs/groups/groups_event.dart';

import '../blocs/contacts/contacts_bloc.dart';
import '../blocs/contacts/contacts_event.dart';

import '../blocs/map/map_bloc.dart';
import '../blocs/map/map_event.dart';

import '../blocs/invitations/invitations_bloc.dart';
import '../blocs/invitations/invitations_event.dart';
import '../blocs/invitations/invitations_state.dart';

import '../models/pending_message.dart';
import '../models/sharing_preferences.dart';

/// Represents the current state of sync initialization
enum SyncState {
  uninitialized,
  loadingToken,
  performingCatchUp,
  processingRooms,
  reconciling,
  ready,
  error,
}

class SyncManager with ChangeNotifier {
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
  final InvitationsBloc invitationsBloc;
  final List<PendingMessage> _pendingMessages = [];
  final MapIconSyncService? mapIconSyncService;
  final LocationManager? locationManager;
  bool _isActive = true;

  bool _isSyncing = false;
  final Map<String, List<Map<String, dynamic>>> _roomMessages = {};
  bool _isInitialized = false;
  String? _sinceToken;
  bool _authenticationFailed = false;
  
  // Elegant sync state management
  SyncState _syncState = SyncState.uninitialized;
  final List<Function> _postSyncOperations = [];
  DateTime? _lastRoomUpdateTime;
  static const Duration _minRoomUpdateInterval = Duration(seconds: 5);


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
      this.invitationsBloc,
      {this.mapIconSyncService,
      this.locationManager}
      );

  List<Map<String, dynamic>> get invites {
    final state = invitationsBloc.state;
    if (state is InvitationsLoaded) {
      return List.unmodifiable(state.invitations);
    }
    return [];
  }
  Map<String, List<Map<String, dynamic>>> get roomMessages => Map.unmodifiable(_roomMessages);
  int get totalInvites {
    final state = invitationsBloc.state;
    if (state is InvitationsLoaded) {
      return state.totalInvites;
    }
    return 0;
  }
  SyncState get syncState => _syncState;
  bool get isReady => _syncState == SyncState.ready;

  Future<void> _loadSinceToken() async {
    final prefs = await SharedPreferences.getInstance();
    _sinceToken = prefs.getString('syncSinceToken');
    print('[SyncManager] Loaded since token: $_sinceToken');
  }

  Future<void> _saveSinceToken(String token) async {
    // Never save empty tokens
    if (token.isEmpty) {
      print('[SyncManager] Warning: Attempted to save empty sync token, ignoring');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('syncSinceToken', token);
    print('[SyncManager] Saved since token: ${token.substring(0, 20)}...');
  }

  Future<void> initialize() async {
    if (_isInitialized || _syncState != SyncState.uninitialized) return;
    
    // Defer state change to avoid build phase conflicts
    await Future.microtask(() => _setSyncState(SyncState.loadingToken));
    print("[SyncManager] Starting initialization sequence");
    
    // Ensure InvitationsBloc is ready before processing sync
    await Future.delayed(const Duration(milliseconds: 200));
    
    try {
      await _loadSinceToken();
      
      // IMPORTANT: Do initial sync BEFORE cleaning rooms
      _setSyncState(SyncState.performingCatchUp);
      
      if (_sinceToken == null) {
        print("[SyncManager] Performing initial full sync...");
        final response = await client.sync(
          fullState: true,
          timeout: 30000,
        );
        
        if (response.nextBatch != null && response.nextBatch!.isNotEmpty) {
          _sinceToken = response.nextBatch;
          await _saveSinceToken(_sinceToken!);
        }
        
        await _processInitialSync(response);
        
        // Wait a moment for client to fully process the sync
        await Future.delayed(const Duration(seconds: 1));
      } else {
        // Even with a saved token, do a quick sync to ensure we're up to date
        print("[SyncManager] Performing catch-up sync from saved token...");
        final response = await client.sync(
          since: _sinceToken,
          timeout: 10000,
        );
        
        // Process any messages that came in while we were offline
        if (response.nextBatch != null && response.nextBatch!.isNotEmpty) {
          _sinceToken = response.nextBatch;
          await _saveSinceToken(_sinceToken!);
        }
        
        // Process the catch-up sync response to get missed messages
        await _processInitialSync(response);
      }
      
      // Process rooms after sync completes
      _setSyncState(SyncState.processingRooms);
      await roomService.cleanRooms();
      
      // Clean up orphaned users immediately after room cleanup
      await _cleanupOrphanedUsers();
      
      // Reconcile state
      _setSyncState(SyncState.reconciling);
      await _reconcileLocalStateWithServer();

      // Refresh contacts and groups after reconciliation
      contactsBloc.add(RefreshContacts());
      groupsBloc.add(RefreshGroups());

      // Start ongoing sync stream
      roomService.getAndUpdateDisplayName();
      await _startSyncStream();

      // Mark as ready and process queued operations
      _isInitialized = true;
      _setSyncState(SyncState.ready);
      await _processQueuedOperations();
    } catch (e) {
      print("[SyncManager] Error during initialization: $e");
      _setSyncState(SyncState.error);
      if (_isAuthenticationError(e)) {
        await _handleAuthenticationFailure();
      }
    }
  }
  
  void _setSyncState(SyncState newState) {
    if (_syncState != newState) {
      print('[SyncManager] State transition: $_syncState -> $newState');
      _syncState = newState;
      // Defer notification to avoid setState during build
      // Using scheduleMicrotask ensures it runs after current build
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }
  
  /// Queue an operation to run after sync completes
  void queuePostSyncOperation(Function operation) {
    if (_syncState == SyncState.ready) {
      // Already ready, execute immediately
      operation();
    } else {
      _postSyncOperations.add(operation);
    }
  }
  
  Future<void> _processQueuedOperations() async {
    print('[SyncManager] Processing ${_postSyncOperations.length} queued operations');
    final operations = List<Function>.from(_postSyncOperations);
    _postSyncOperations.clear();
    
    for (final operation in operations) {
      try {
        await operation();
      } catch (e) {
        print('[SyncManager] Error processing queued operation: $e');
      }
    }
  }



  StreamSubscription<SyncUpdate>? _syncSubscription;
  
  Future<void> _startSyncStream() async {
    if (_syncSubscription != null) return;
    
    _syncSubscription = client.onSync.stream.listen(
      (syncUpdate) async {
        await _processSyncUpdate(syncUpdate);
      },
      onError: (error) {
        print("Sync stream error: $error");
        if (_isAuthenticationError(error)) {
          _handleAuthenticationFailure();
        }
      },
    );
    
    // Check if the client is already syncing before starting a new sync
    if (!client.syncPending) {
      _isSyncing = true;
      await client.sync(
        since: _sinceToken,
        timeout: 30000,
        setPresence: PresenceType.unavailable,
      );
    } else {
      _isSyncing = true;
    }
  }
  
  Future<void> _processSyncUpdate(SyncUpdate syncUpdate) async {
    if (syncUpdate.nextBatch != null && syncUpdate.nextBatch!.isNotEmpty) {
      _sinceToken = syncUpdate.nextBatch;
      await _saveSinceToken(_sinceToken!);
    }
    
    syncUpdate.rooms?.invite?.forEach(_processInvite);
    
    // Process joined rooms with async/await
    if (syncUpdate.rooms?.join != null) {
      for (var entry in syncUpdate.rooms!.join!.entries) {
        final roomId = entry.key;
        final joinedRoomUpdate = entry.value;
        await _processRoomMessages(roomId, joinedRoomUpdate);
        if ((joinedRoomUpdate.state ?? []).isNotEmpty) {
          await _processRoomJoin(roomId, joinedRoomUpdate);
        }
      }
    }
    
    syncUpdate.rooms?.leave?.forEach(_processRoomLeaveOrKick);
  }
  
  Future<void> startSync() async {
    await _startSyncStream();
  }

  void handleAppLifecycleState(bool isActive) {
    _isActive = isActive;
    if (isActive) {
      if (_pendingMessages.isNotEmpty) {
        _processPendingMessages();
      }
      mapBloc.add(MapLoadUserLocations());
      
      if (!_isSyncing || !client.syncPending) {
        _startSyncStream();
      }
    }
  }

  Future<void> stopSync() async {
    if (!_isSyncing && !client.syncPending) return;
    
    _isSyncing = false;
    _syncSubscription?.cancel();
    _syncSubscription = null;
    
    if (client.syncPending) {
      client.abortSync();
    }
  }

  void _processInvite(String roomId, InvitedRoomUpdate inviteUpdate) {
    if (!_inviteExists(roomId)) {
      final inviter = _extractInviter(inviteUpdate);
      final roomName = _extractRoomName(inviteUpdate) ?? 'Unnamed Room';

      invitationsBloc.add(ProcessSyncInvitation(
        roomId: roomId,
        inviter: inviter,
        roomName: roomName,
        inviteState: inviteUpdate.inviteState,
      ));
      
      notifyListeners();
    }
  }

  Future<void> clearAllState() async {
    invitationsBloc.add(ClearInvitations());
    _roomMessages.clear();
    _pendingMessages.clear();
    _isInitialized = false;
    _isSyncing = false;

    // Clear the sync token so next login does a full sync
    _sinceToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sync_since_token');

    // Reset sync state to uninitialized so it can start fresh
    _syncState = SyncState.uninitialized;

    // Stop syncing
    await stopSync();
    // Notify listeners of the changes
    notifyListeners();
  }

  Future<void> _processRoomLeave(String roomId, LeftRoomUpdate leftRoomUpdate) async {
    try {
      print("[LEAVE] Starting _processRoomLeave for room: $roomId");
      final room = await roomRepository.getRoomById(roomId);
      if (room == null) {
        print("[LEAVE] Room $roomId not found in database");
        return;
      }

      if (room.isGroup) {
        // Handle leaving a group
        print("[LEAVE GROUP] Processing group leave for room: ${room.name}");
        print("[LEAVE GROUP] Getting participants...");
        final participants = await roomRepository.getRoomParticipants(roomId);
        print("[LEAVE GROUP] Found ${participants.length} participants: $participants");
        
        // For each participant in the group we just left
        for (final participantId in participants) {
          if (participantId == client.userID) {
            print("[LEAVE GROUP] Skipping self: $participantId");
            continue;
          }
          
          print("[LEAVE GROUP] Processing participant: $participantId");
          
          // Remove relationship for this room
          await userRepository.removeUserRelationship(participantId, roomId);
          
          // Check if we're still connected to this user (direct contact or other shared groups)
          final isDirectContact = await userRepository.getDirectRoomForContact(participantId) != null;
          print("[LEAVE GROUP] Is direct contact: $isDirectContact");
          
          // Check if we share any other groups with this user
          final myRooms = await roomRepository.getUserRooms(client.userID!);
          final theirRooms = await roomRepository.getUserRooms(participantId);
          
          print("[LEAVE GROUP] My rooms: $myRooms");
          print("[LEAVE GROUP] Their rooms: $theirRooms");
          
          // Find shared groups (excluding the one we just left)
          bool hasSharedGroups = false;
          for (final myRoom in myRooms) {
            if (myRoom != roomId && theirRooms.contains(myRoom)) {
              final roomData = await roomRepository.getRoomById(myRoom);
              if (roomData != null && roomData.isGroup) {
                hasSharedGroups = true;
                print("[LEAVE GROUP] Found shared group: $myRoom");
                break;
              }
            }
          }
          
          print("[LEAVE GROUP] Has shared groups: $hasSharedGroups");
          
          if (!isDirectContact && !hasSharedGroups) {
            // Not a direct contact and not in any other shared groups - remove from map
            print("[LEAVE GROUP] REMOVING $participantId from map - no longer connected");
            await locationRepository.deleteUserLocations(participantId);
            await userRepository.deleteUser(participantId);
            mapBloc.add(RemoveUserLocation(participantId));
          } else {
            print("[LEAVE GROUP] KEEPING $participantId - direct contact: $isDirectContact, shared groups: $hasSharedGroups");
          }
        }
        
        // Now delete the room from our database
        await roomRepository.deleteRoom(roomId);
        await roomRepository.removeAllParticipants(roomId);
        
        // Update UI
        groupsBloc.add(RefreshGroups());
        mapBloc.add(MapLoadUserLocations());
        
      } else {
        // Handle direct room leave
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
      // SAFETY: Verify this is a real leave event, not an error or incomplete sync
      // Check if we can still access the room on the client
      final clientRoom = client.getRoomById(roomId);
      if (clientRoom != null && clientRoom.membership == Membership.join) {
        print("[SyncManager] Received leave event for $roomId but still joined - ignoring (likely sync error)");
        return;
      }
      
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

  Future<void> _processRoomMessages(String roomId, JoinedRoomUpdate joinedRoomUpdate) async {
    final timelineEvents = joinedRoomUpdate.timeline?.events ?? [];
    for (var event in timelineEvents) {
      // Debug log event type and sender
      if (event.type == 'm.room.message') {
        print('[Sync Debug] Processing ${event.type} from ${event.senderId} in room $roomId');
      }
      
      // Check for member events in timeline (when someone accepts an invite or leaves)
      if (event.type == 'm.room.member' && event.stateKey != null) {
        final membershipStatus = event.content['membership'] as String?;
        final prevMembership = event.prevContent?['membership'] as String?;
        
        print("[SyncManager] Timeline member event: ${event.stateKey} from $prevMembership to $membershipStatus");
        
        // Handle member leave events
        if (membershipStatus == 'leave' && event.stateKey != client.userID) {
          print("[SyncManager] Detected ${event.stateKey} left room $roomId");
          await _handleMemberLeave(roomId, event.stateKey);
        }
        // If someone just joined (accepted invite), send them our location
        // prevMembership can be 'invite' or null (if we don't have previous state)
        // BUT: Skip if this is us joining (we see our own join event)
        else if (membershipStatus == 'join' && event.stateKey != client.userID) {
          print("[SyncManager] Detected ${event.stateKey} joined room $roomId (prev: $prevMembership)");
          
          // Only send if they weren't already in the room
          if (prevMembership != 'join') {
            print("[SyncManager] User ${event.stateKey} is newly joined, sending avatar and initial location");
            
            // IMPORTANT: Send our avatar when they accept our invite (bidirectional exchange)
            try {
              final avatarService = AvatarAnnouncementService(client);
              print("[Avatar Exchange] Timeline: Sending our avatar to ${event.stateKey} who just joined");
              await avatarService.announceProfPicToRoom(roomId);
              
              // For groups, also send avatar state, group avatar, and map icons
              final room = await roomRepository.getRoomById(roomId);
              if (room != null && room.isGroup) {
                // Send all member avatars
                await avatarService.sendAvatarState(roomId, targetUserId: event.stateKey);
                
                // Send group avatar
                print("[Avatar Exchange] Sending group avatar to new member");
                await avatarService.announceGroupAvatarToRoom(roomId);
                
                // Send all map icons to new member
                if (mapIconSyncService != null) {
                  // Small delay to ensure the new member's session is ready
                  Future.delayed(const Duration(seconds: 1), () async {
                    print('[MapIconSync] Timeline: Sending icon state to new member ${event.stateKey}');
                    await mapIconSyncService!.sendIconState(roomId, targetUserId: event.stateKey);
                  });
                }
              }
            } catch (e) {
              print("[Avatar Exchange] Error sending avatar in timeline event: $e");
            }
            
            try {
              final room = await roomRepository.getRoomById(roomId);
              if (room != null) {
                // Check sharing preferences for direct rooms
                if (!room.isGroup) {
                  final sharingPrefs = await sharingPreferencesRepository.getSharingPreferences(event.stateKey!, 'user');
                  final isSharingEnabled = sharingPrefs?.activeSharing ?? true;
                  
                  if (isSharingEnabled) {
                    print("[SyncManager] Sharing enabled for ${event.stateKey}, sending location to room $roomId");
                    await locationManager?.grabLocationAndPing();
                    await roomService.updateSingleRoom(roomId);
                    print("[SyncManager] Successfully sent initial location to ${event.stateKey}");
                  } else {
                    print("[SyncManager] Sharing disabled for ${event.stateKey}, not sending location");
                  }
                } else {
                  // For groups, always send
                  print("[SyncManager] Group room, sending location to new member ${event.stateKey}");
                  await locationManager?.grabLocationAndPing();
                  await roomService.updateSingleRoom(roomId);
                  print("[SyncManager] Successfully sent initial location to group member ${event.stateKey}");
                }
              } else {
                print("[SyncManager] Warning: Room $roomId not found in local database");
              }
            } catch (e) {
              print("[SyncManager] Error sending location on invite accept: $e");
            }
          }
        }
      }
      
      if (!_isActive) {
        // Queue message if app is in background
        print('[Sync Debug] App inactive, queuing event ${event.eventId}');
        _pendingMessages.add(PendingMessage(
          roomId: roomId,
          eventId: event.eventId ?? '',
          event: event,
        ));
        continue;
      }

      try {
        final message = await messageProcessor.processEvent(roomId, event);
        if (message != null) {
          _roomMessages.putIfAbsent(roomId, () => []).add(message);
          notifyListeners();
        }
      } catch (e) {
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
      }
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
        await initialProcessRoom(matrixRoom);
        
        final processedRoom = await roomRepository.getRoomById(roomId);
        if (processedRoom != null) {
          groupsBloc.add(RefreshGroups());
        }
      }
    } catch (e) {
      print("Error in handleNewGroupCreation: $e");
    }
  }

  Future<void> _processRoomJoin(String roomId, JoinedRoomUpdate joinedRoomUpdate) async {
    try {
      print("Processing room join for room: $roomId");
      final stateEvents = joinedRoomUpdate.state ?? [];
      print("Found ${stateEvents.length} state events");

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
        print("Processing initial room join");
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
        }
        return;
      }

      // Second pass: Process individual state events
      for (var event in stateEvents) {
        print("Processing event type: ${event.type}");
        if (event.type == 'm.room.member') {
          // Always process member state events, including leaves
          await _processMemberStateEvent(roomId, event);
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
    } catch (e) {
      print('Error processing room join: $e');
    }
  }

  Future<void> _processMemberStateEvent(String roomId, MatrixEvent event) async {
    print("Processing member event: ${event.stateKey} with content: ${event.content}");

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

        groupsBloc.add(UpdateGroup(roomId));

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
          // Check if this is a new member joining (not us)
          final prevMembership = event.prevContent?['membership'] as String?;
          print("[SyncManager] Member state change: ${event.stateKey} from $prevMembership to $membershipStatus");
          
          // Check if someone else (not us) just joined the room
          // prevMembership could be: null (first time), 'invite' (accepted), 'leave' (rejoined), etc.
          if (event.stateKey != client.userID && membershipStatus == 'join' && prevMembership != 'join') {
            print("New member joined: ${event.stateKey} (was: ${prevMembership ?? 'never joined before'}), initiating bidirectional avatar exchange");
            
            // Initialize avatar service
            final avatarService = AvatarAnnouncementService(client);
            
            try {
              // BIDIRECTIONAL AVATAR EXCHANGE
              // 1. Send our profile picture to the new member
              await avatarService.announceProfPicToRoom(roomId);
              
              // 2. For groups, send avatar state bundle with all member avatars
              if (room.isGroup) {
                // Send avatar state bundle to help new member get all avatars
                print("[Avatar Exchange] Sending avatar state bundle to new group member ${event.stateKey}");
                await avatarService.sendAvatarState(roomId, targetUserId: event.stateKey);
                
                // Any group member sends the group avatar
                print("[Avatar Exchange] Sending group avatar to new member");
                await avatarService.announceGroupAvatarToRoom(roomId);
                
                // Send map icon state to new group member
                if (mapIconSyncService != null) {
                  // Small delay to ensure the new member is fully joined
                  Future.delayed(const Duration(seconds: 1), () async {
                    print('[MapIconSync] Sending icon state to new member ${event.stateKey} in room $roomId');
                    await mapIconSyncService!.sendIconState(roomId, targetUserId: event.stateKey);
                  });
                }
              }
              
              // Send our location once when they join (if sharing is enabled)
              if (!room.isGroup) {
                // For direct rooms, check sharing preferences
                final sharingPrefs = await sharingPreferencesRepository.getSharingPreferences(event.stateKey!, 'user');
                final isSharingEnabled = sharingPrefs?.activeSharing ?? true; // Default to true if no prefs
                
                if (isSharingEnabled) {
                  print("New member joined direct room, sending initial location");
                  // Grab fresh location and send it
                  try {
                    await locationManager?.grabLocationAndPing();
                    await roomService.updateSingleRoom(roomId);
                    print("Sent initial location to ${event.stateKey} in room $roomId");
                  } catch (e) {
                    print("Error sending initial location: $e");
                  }
                } else {
                  print("Location sharing disabled for ${event.stateKey}, not sending initial location");
                }
              } else {
                // For group rooms, always send location when someone joins
                print("New member joined group room, sending initial location");
                try {
                  await locationManager?.grabLocationAndPing();
                  await roomService.updateSingleRoom(roomId);
                  print("Sent initial location to new group member ${event.stateKey} in room $roomId");
                } catch (e) {
                  print("Error sending initial location to group: $e");
                }
              }
            } catch (e) {
              print('Error during bidirectional avatar exchange: $e');
            }
          } else if (event.stateKey == client.userID && membershipStatus == 'join' && prevMembership == 'invite') {
            // We just accepted an invite - request avatars from others
            print("[Avatar Exchange] We accepted invite to room $roomId, requesting avatars");
            try {
              final avatarService = AvatarAnnouncementService(client);
              
              // Request avatars from all room members
              await avatarService.requestAvatars(roomId);
            } catch (e) {
              print('Error requesting avatars after accepting invite: $e');
            }
          }
          
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

          // Update UI based on room type
          if (room.isGroup) {
            groupsBloc.add(UpdateGroup(roomId));
          } else {
            print("Direct room join detected, refreshing contacts");
            contactsBloc.add(RefreshContacts());
          }
        } catch (e) {
          print('Error updating user profile for ${event.stateKey}: $e');
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

          // Check if we're still connected to this user in any way BEFORE removing them from DB
          final hasDirectRoom = await userRepository.getDirectRoomForContact(userId);
          
          // Check if we share any OTHER groups with this user
          // IMPORTANT: Must check this BEFORE removing them from the room participants
          final myRooms = await roomRepository.getUserRooms(client.userID!);
          final theirRooms = await roomRepository.getUserRooms(userId);  // This still includes current room
          
          bool inOtherSharedGroups = false;
          for (final myRoom in myRooms) {
            // Skip the current room they're being removed from
            if (myRoom != roomId && theirRooms.contains(myRoom)) {
              // This is a room we BOTH are in - check if it's a group
              final roomData = await roomRepository.getRoomById(myRoom);
              if (roomData != null && roomData.isGroup) {
                print("[_handleMemberLeave] User $userId is in shared group: $myRoom");
                inOtherSharedGroups = true;
                break;
              }
            }
          }
          
          print("[_handleMemberLeave] User $userId - hasDirectRoom: ${hasDirectRoom != null}, inOtherSharedGroups: $inOtherSharedGroups");

          // NOW we can remove them from this room's participants
          await userRepository.removeUserRelationship(userId, roomId);
          await roomRepository.removeRoomParticipant(roomId, userId);
          await userRepository.updateMembershipStatus(userId, roomId, 'leave');

          if (!inOtherSharedGroups && hasDirectRoom == null) {
            print("User not in any other shared rooms/contacts, removing from map");
            await locationRepository.deleteUserLocations(userId);
            await userRepository.deleteUser(userId);
            mapBloc.add(RemoveUserLocation(userId));
          } else {
            print("User still connected via other rooms, keeping on map");
          }

          // Update UI with staggered refreshes
          groupsBloc.add(LoadGroupMembers(roomId));
          groupsBloc.add(UpdateGroup(roomId));
          groupsBloc.add(RefreshGroups());

          // Additional delayed updates to ensure sync
          Future.delayed(const Duration(milliseconds: 500), () {
            groupsBloc.add(LoadGroups());
            groupsBloc.add(LoadGroupMembers(roomId));
          });

        } catch (e) {
          print('Error processing group member leave: $e');
        }
      } else {
        // Handle direct room cleanup
        await userRepository.removeContact(userId);
        await roomRepository.deleteRoom(roomId);

        // Check if user is in any shared groups with us
        final userRooms = await roomRepository.getUserRooms(userId);
        final myRooms = await roomRepository.getUserRooms(client.userID!);
        
        // Find shared group rooms
        final sharedGroups = <String>[];
        for (final userRoom in userRooms) {
          if (myRooms.contains(userRoom)) {
            final room = await roomRepository.getRoomById(userRoom);
            if (room != null && room.isGroup) {
              sharedGroups.add(userRoom);
            }
          }
        }
        
        if (sharedGroups.isEmpty) {
          // Not in any shared groups, remove from map and delete location
          await locationRepository.deleteUserLocations(userId);
          mapBloc.add(RemoveUserLocation(userId));
          
          // Clean up user record if they have no rooms at all
          if (userRooms.isEmpty) {
            await userRepository.deleteUser(userId);
          }
        } else {
          // Still in shared groups, keep them on map but refresh to ensure proper state
          print("[SyncManager] User $userId still in ${sharedGroups.length} shared groups, keeping on map");
          mapBloc.add(MapLoadUserLocations());
        }

        contactsBloc.add(RefreshContacts());
      }
    }
  }

  Future<void> _processInitialSync(SyncUpdate response) async {
    print('[Sync Debug] Processing initial sync response');
    print('[Sync Debug] Rooms in response - Joined: ${response.rooms?.join?.length ?? 0}, Invited: ${response.rooms?.invite?.length ?? 0}');
    
    response.rooms?.invite?.forEach(_processInvite);
    
    // Process all joined rooms and wait for message processing
    if (response.rooms?.join != null) {
      for (var entry in response.rooms!.join!.entries) {
        final roomId = entry.key;
        final joinedRoomUpdate = entry.value;
        final timelineEventCount = joinedRoomUpdate.timeline?.events?.length ?? 0;
        if (timelineEventCount > 0) {
          print('[Sync Debug] Room $roomId has $timelineEventCount timeline events to process');
        }
        await _processRoomMessages(roomId, joinedRoomUpdate);
        if ((joinedRoomUpdate.state ?? []).isNotEmpty) {
          await _processRoomJoin(roomId, joinedRoomUpdate);
        }
      }
    }
    
    response.rooms?.leave?.forEach(_processRoomLeaveOrKick);

    for (var room in client.rooms) {
      if (room.membership == Membership.join) {
        initialProcessRoom(room);
      }
    }

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
    // Skip non-Grid rooms entirely - they should be left/deleted
    if (!room.name.startsWith('Grid:')) {
      print('Skipping non-Grid room during processing: ${room.name ?? 'Unnamed'} (${room.id})');
      return;
    }
    
    // Check if the room already exists
    final existingRoom = await roomRepository.getRoomById(room.id);

    final isDirect = isDirectRoom(room.name ?? '');
    final customRoom = GridRoom.Room(
      roomId: room.id,
      name: room.name ?? 'Unnamed Room',
      isGroup: !isDirect,
      lastActivity: DateTime.now().toIso8601String(),
      avatarUrl: room.avatar?.toString(),
      members: room.getParticipants().map((p) => p.id).toList(),
      expirationTimestamp: extractExpirationTimestamp(room.name ?? ''),
    );

    if (existingRoom == null) {
      // Insert new room
      await roomRepository.insertRoom(customRoom);
      print('Inserted new room: ${room.id}');
    } else {
      // Update existing room
      await roomRepository.updateRoom(customRoom);
      print('Updated existing room: ${room.id}');
    }

    // Sync participants
    final currentParticipants = customRoom.members;
    final existingParticipants = await roomRepository.getRoomParticipants(room.id);

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
        
        // Also insert into RoomParticipants table for proper tracking
        await roomRepository.insertRoomParticipant(room.id, participantId);

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

        final customRoom = await roomRepository.getRoomById(room.id);
        if (customRoom?.isGroup ?? false) {

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
        }
        print('Processed user ${participantId} in room ${room.id}');
      } catch (e) {
        print('Error fetching profile for user $participantId: $e');
      }
    }

    // Remove participants who are no longer in the room
    for (var participant in existingParticipants) {
      if (!currentParticipants.contains(participant)) {
        await roomRepository.removeRoomParticipant(room.id, participant);
        print('Removed participant $participant from room ${room.id}');
      }
    }
    
    // Update group UI ONCE after all participants are processed
    if (customRoom.isGroup) {
      print('Updating group in bloc: ${room.id}');
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
        
        // Small delay to ensure UI updates
        await Future.delayed(const Duration(milliseconds: 100));

        final room = client.getRoomById(roomId);
        if (room != null) {
          await processJoinedRoom(room);
          
          // Enhanced avatar exchange after accepting invite
          try {
            final avatarService = AvatarAnnouncementService(client);
            
            // 1. Announce our avatar to the room
            await avatarService.announceProfPicToRoom(roomId);
            
            // 2. Request avatars from all room members
            print('[Avatar Exchange] Requesting avatars from room members after accepting invite');
            await avatarService.requestAvatars(roomId);
            
            // 4. For groups, existing members should send avatar state
            // This is handled by the member join event in _processMemberStateEvent
            
          } catch (e) {
            print('Error during avatar exchange after accepting invite: $e');
          }
          
          groupsBloc.add(RefreshGroups());
        }
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
    final state = invitationsBloc.state;
    if (state is InvitationsLoaded) {
      return state.invitations.any((invite) => invite['roomId'] == roomId);
    }
    return false;
  }

  void clearInvites() {
    invitationsBloc.add(ClearInvitations());
    notifyListeners();
  }

  void clearRoomMessages(String roomId) {
    _roomMessages.remove(roomId);
    notifyListeners();
  }

  void removeInvite(String roomId) {
    invitationsBloc.add(RemoveInvitation(roomId));
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
      
      // Additional safety: Don't reconcile if we have very few server rooms compared to local
      // This might indicate incomplete sync
      if (serverRooms.length < localRooms.length / 2 && localRooms.length > 2) {
        print("[SyncManager] WARNING: Server has significantly fewer rooms (${serverRooms.length}) than local (${localRooms.length})");
        print("[SyncManager] This might indicate incomplete sync, skipping reconciliation");
        return;
      }
      
      final serverRoomIds = serverRooms.map((r) => r.id).toSet();
      final localRoomIds = localRooms.map((r) => r.roomId).toSet();
      
      // 2. Find discrepancies
      final roomsOnServerButNotLocal = serverRoomIds.difference(localRoomIds);
      final roomsInLocalButNotServer = localRoomIds.difference(serverRoomIds);
      
      print("[SyncManager] Reconciliation summary:");
      print("  - Server rooms: ${serverRoomIds.length}");
      for (final room in serverRooms) {
        print("    * ${room.name ?? 'Unnamed'} (${room.id})");
      }
      print("  - Local rooms: ${localRoomIds.length}");
      for (final room in localRooms) {
        print("    * ${room.name} (${room.roomId})");
      }
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
      
      // 7. Refresh UI
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
      // Add a small delay to ensure room participants are fully synced
      await Future.delayed(const Duration(seconds: 2));
      
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
  
  // Public method to manually trigger cleanup of orphaned location data
  Future<void> cleanupOrphanedLocationData() async {
    try {
      print("[SyncManager] Starting manual cleanup of orphaned location data...");
      
      // Get all locations from the database
      final allLocations = await locationRepository.getAllLatestLocations();
      
      for (final location in allLocations) {
        // Skip own user
        if (location.userId == client.userID) continue;
        
        // Check if user exists in any rooms
        final userRooms = await roomRepository.getUserRooms(location.userId);
        final directRoom = await userRepository.getDirectRoomForContact(location.userId);
        
        if (userRooms.isEmpty && directRoom == null) {
          print("[SyncManager] Found orphaned location for user: ${location.userId}");
          await locationRepository.deleteUserLocations(location.userId);
          mapBloc.add(RemoveUserLocation(location.userId));
          
          // Also check if the user record itself is orphaned
          final user = await userRepository.getUserById(location.userId);
          if (user != null) {
            print("[SyncManager] Also removing orphaned user record: ${location.userId}");
            await userRepository.deleteUser(location.userId);
          }
        }
      }
      
      // Refresh map after cleanup
      mapBloc.add(MapLoadUserLocations());
      
      print("[SyncManager] Orphaned location cleanup complete");
    } catch (e) {
      print("[SyncManager] Error during manual location cleanup: $e");
    }
  }

  bool _isAuthenticationError(dynamic error) {
    if (error is MatrixException) {
      // Only M_UNKNOWN_TOKEN definitively means the token is invalid
      if (error.errcode == 'M_UNKNOWN_TOKEN') {
        print("M_UNKNOWN_TOKEN detected - invalid access token");
        return true;
      }
    }
    return false;
  }

  Future<void> _handleAuthenticationFailure() async {
    try {
      // Clear all local state
      await clearAllState();
      
      // Clear stored credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      // Force logout from matrix client
      if (client.isLogged()) {
        try {
          await client.logout();
        } catch (e) {
          // Ignore logout errors since token is already invalid
          print("Logout error (ignored): $e");
        }
      }
      
      // Set authentication failed flag
      _authenticationFailed = true;
      notifyListeners();
    } catch (e) {
      print("Error handling authentication failure: $e");
    }
  }

  bool get authenticationFailed => _authenticationFailed;
}
