import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class SyncManager with ChangeNotifier {
  final Client client;
  bool _isSyncing = false;
  final List<Map<String, dynamic>> _invites = [];

  SyncManager(this.client);

  // Existing getter for invites
  List<Map<String, dynamic>> get invites => List.unmodifiable(_invites);

  // **Add this getter to return the total number of invites**
  int get totalInvites => _invites.length;

  Future<void> startSync() async {
    if (_isSyncing) return;

    _isSyncing = true;
    client.sync();

    client.onSync.stream.listen((SyncUpdate syncUpdate) {
      // Process invited rooms
      syncUpdate.rooms?.invite?.forEach((roomId, InvitedRoomUpdate inviteUpdate) {
        final inviter = _extractInviter(inviteUpdate);
        final roomName = _extractRoomName(inviteUpdate) ?? 'Unnamed Room';

        final inviteData = {
          'roomId': roomId,
          'inviter': inviter,
          'roomName': roomName,
          'inviteState': inviteUpdate.inviteState,
        };

        // Add to list if not already present
        if (!_invites.any((invite) => invite['roomId'] == roomId)) {
          _invites.add(inviteData);
          notifyListeners(); // Notify UI of new invites
        }
      });
    });
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

  void clearInvites() {
    _invites.clear();
    notifyListeners();
  }

  void removeInvite(String roomId) {
    _invites.removeWhere((invite) => invite['roomId'] == roomId);
    notifyListeners(); // Notify UI to update
  }

  Future<void> stopSync() async {
    if (!_isSyncing) return;

    _isSyncing = false;
    client.abortSync();
  }
}
