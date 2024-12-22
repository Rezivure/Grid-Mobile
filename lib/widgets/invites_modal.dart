import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/widgets/friend_request_modal.dart';
import 'package:grid_frontend/widgets/group_invitation_modal.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/services/room_service.dart';

class InvitesModal extends StatelessWidget {
  final RoomService roomService;
  final Future<void> Function() onInviteHandled;

  InvitesModal({required this.onInviteHandled, required this.roomService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Access the SyncManager
    final syncManager = Provider.of<SyncManager>(context);

    return Material(
      color: colorScheme.background,
      child: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onBackground,
                ),
              ),
              Expanded(
                child: syncManager.invites.isEmpty
                    ? Center(
                  child: Text(
                    'No notifications found',
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                )
                    : ListView.builder(
                  itemCount: syncManager.invites.length,
                  itemBuilder: (context, index) {
                    final invite = syncManager.invites[index];
                    final inviterId = invite['inviter'] ?? 'Unknown';
                    final roomId = invite['roomId'] ?? 'Unknown';
                    final roomName = invite['roomName'] ?? 'Unnamed Room';
                    final isDirectInvite =
                    roomName.startsWith("Grid:Direct");

                    String displayGroupName = 'Unnamed Group';
                    if (!isDirectInvite) {
                      // Extract groupName from roomName
                      final parts = roomName.split(':');
                      if (parts.length > 3) {
                        displayGroupName = parts[3]; // groupName
                      } else {
                        displayGroupName = roomName;
                      }
                    }

                    return ListTile(
                      leading: RandomAvatar(
                        localpart(inviterId),
                        height: 60,
                        width: 60,
                      ),
                      title: Text(
                        '@${inviterId.split(":").first.replaceFirst("@", "")}',
                        style:
                        TextStyle(color: colorScheme.onBackground),
                      ),
                      subtitle: Text(
                        isDirectInvite
                            ? 'wants to connect with you.'
                            : 'want you to join their group.',
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      onTap: () {
                        _handleInviteTap(
                          context,
                          roomId,
                          roomName,
                          inviterId,
                          isDirectInvite,
                        );
                      },
                    );
                  },
                ),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.onSurface,
                  foregroundColor: colorScheme.surface,
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleInviteTap(
      BuildContext context,
      String roomId,
      String roomName,
      String inviterId,
      bool isDirectInvite,
      ) {
    if (isDirectInvite) {
      // Extract the display name from the inviterId
      final displayName = inviterId.split(":").first.replaceFirst("@", "");

      showDialog(
        context: context,
        builder: (context) => FriendRequestModal(
          roomService: roomService,
          userId: inviterId,
          displayName: displayName,
          roomId: roomId,
          onResponse: () async {
            // Callback to refresh invites list after action
            await onInviteHandled();
          },
        ),
      );
    } else {
      // Extract group name and expiration
      int expiration = -1;
      String groupName = 'Unnamed Group';
      final parts = roomName.split(':');
      if (parts.length > 3) {
        expiration = int.tryParse(parts[2]) ?? -1;
        groupName = parts[3]; // groupName
      }

      showDialog(
        context: context,
        builder: (context) => GroupInvitationModal(
          roomService: roomService,
          groupName: groupName,
          roomId: roomId,
          inviter: inviterId,
          expiration: expiration,
          refreshCallback: () async {
            // Callback to refresh invites list after action
            await onInviteHandled();
          },
        ),
      );
    }
  }

}
