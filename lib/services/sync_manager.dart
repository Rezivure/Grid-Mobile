import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/services/message_processor.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:provider/provider.dart';

class SyncManager with ChangeNotifier {
  final Client client;
  final MessageProcessor messageProcessor;
  bool _isSyncing = false;
  final List<Map<String, dynamic>> _invites = [];
  final Map<String, List<Map<String, dynamic>>> _roomMessages = {};
  bool _isInitialized = false;

  SyncManager(this.client, this.messageProcessor);

  List<Map<String, dynamic>> get invites => List.unmodifiable(_invites);
  Map<String, List<Map<String, dynamic>>> get roomMessages => Map.unmodifiable(_roomMessages);
  int get totalInvites => _invites.length;

  Future<void> initialize() async {
    if (_isInitialized) return; // Prevent re-initialization
    _isInitialized = true;

    print("Initializing Sync Manager");
    await fetchInitialInvites();
    await startSync();
  }

  Future<void> startSync() async {
    if (_isSyncing) return;

    _isSyncing = true;
    client.sync();

    client.onSync.stream.listen((SyncUpdate syncUpdate) {
      // Process invites
      syncUpdate.rooms?.invite?.forEach((roomId, inviteUpdate) {
        _processInvite(roomId, inviteUpdate);
      });

      // Process room messages
      syncUpdate.rooms?.join?.forEach((roomId, joinedRoomUpdate) {
        _processRoomMessages(roomId, joinedRoomUpdate);
      });
    });
  }

  Future<void> stopSync() async {
    if (!_isSyncing) return;

    _isSyncing = false;
    client.abortSync();
  }

  void _processInvite(String roomId, InvitedRoomUpdate inviteUpdate) {
    if (!_inviteExists(roomId)) {
      final inviter = _extractInviter(inviteUpdate);
      final roomName = _extractRoomName(inviteUpdate) ?? 'Unnamed Room';

      final inviteData = {
        'roomId': roomId,
        'inviter': inviter,
        'roomName': roomName,
        'inviteState': inviteUpdate.inviteState,
      };

      _invites.add(inviteData);
      notifyListeners();
    }
  }

  void _processRoomMessages(String roomId, JoinedRoomUpdate joinedRoomUpdate) {
    final timelineEvents = joinedRoomUpdate.timeline?.events ?? [];
    for (var event in timelineEvents) {
      // Process and decrypt the event, returning a message map if applicable
      messageProcessor.processEvent(roomId, event).then((message) {
        if (message != null) {
          _roomMessages.putIfAbsent(roomId, () => []).add(message);
          notifyListeners();
        }
      }).catchError((e) {
        print("Error processing event ${event.eventId}: $e");
      });
    }
  }

  Future<void> fetchInitialInvites() async {
    try {
      final response = await client.sync(fullState: true);
      response.rooms?.invite?.forEach((roomId, inviteUpdate) {
        _processInvite(roomId, inviteUpdate);
      });
      notifyListeners();
    } catch (e) {
      print("Error fetching initial invites: $e");
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
    return _invites.any((invite) => invite['roomId'] == roomId);
  }

  void clearInvites() {
    _invites.clear();
    notifyListeners();
  }

  void clearRoomMessages(String roomId) {
    _roomMessages.remove(roomId);
    notifyListeners();
  }

  void removeInvite(String roomId) {
    _invites.removeWhere((invite) => invite['roomId'] == roomId);
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
}
