import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/widgets/friend_request_modal.dart';
import 'package:grid_frontend/widgets/group_invitation_modal.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:grid_frontend/blocs/invitations/invitations_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_state.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/services/room_service.dart';

class InvitesModal extends StatefulWidget {
  final RoomService roomService;
  final Future<void> Function() onInviteHandled;

  InvitesModal({required this.onInviteHandled, required this.roomService});
  
  @override
  _InvitesModalState createState() => _InvitesModalState();
}

class _InvitesModalState extends State<InvitesModal> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocBuilder<InvitationsBloc, InvitationsState>(
      buildWhen: (previous, current) {
        // Force rebuild on any state change
        print('[InvitesModal] State changed - rebuilding. Current invites: ${current is InvitationsLoaded ? current.invitations.length : 0}');
        return true;
      },
      builder: (context, state) {
        final invites = state is InvitationsLoaded ? state.invitations : [];
        
        void handleInviteTap(
          BuildContext context,
          String roomId,
          String roomName,
          String inviterId,
          bool isDirectInvite,
        ) {
          if (isDirectInvite) {
            // Extract the display name from the inviterId
            final displayName = inviterId.split(":").first.replaceFirst("@", "");

            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (BuildContext context) {
                return FriendRequestModal(
                  userId: inviterId,
                  displayName: displayName,
                  roomId: roomId,
                  roomService: widget.roomService,
                  onResponse: () async {
                    // Force state update by triggering setState
                    if (mounted) {
                      setState(() {});
                    }
                    // Callback to refresh invites list after action
                    await widget.onInviteHandled();
                  },
                );
              },
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
            
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (BuildContext context) {
                return GroupInvitationModal(
                  groupName: groupName,
                  inviter: inviterId,
                  roomId: roomId,
                  expiration: expiration,
                  roomService: widget.roomService,
                  refreshCallback: () async {
                    // Force state update by triggering setState
                    if (mounted) {
                      setState(() {});
                    }
                    // Callback to refresh invites list after action
                    await widget.onInviteHandled();
                  },
                );
              },
            );
          }
        }
        
        return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.background,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // Handle indicator
            Container(
              margin: EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onBackground.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header Section
            Container(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.notifications,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onBackground,
                          ),
                        ),
                        if (invites.isNotEmpty)
                          Text(
                            '${invites.length} pending request${invites.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onBackground.withOpacity(0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content Section
            Expanded(
              child: invites.isEmpty
                  ? Center(
                      child: Container(
                        padding: EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                          Container(
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.notifications_none,
                              color: colorScheme.onSurface.withOpacity(0.4),
                              size: 48,
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No notifications',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Friend requests and group invites will appear here',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurface.withOpacity(0.4),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      itemCount: invites.length,
                      itemBuilder: (context, index) {
                        final invite = invites[index];
                        final inviterId = invite['inviter'] ?? 'Unknown';
                        final roomId = invite['roomId'] ?? 'Unknown';
                        final roomName = invite['roomName'] ?? 'Unnamed Room';
                        final isDirectInvite = roomName.startsWith("Grid:Direct");

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

                        return Container(
                          margin: EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.15),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withOpacity(0.05),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.all(16),
                            leading: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: CircleAvatar(
                                radius: 25,
                                backgroundColor: Colors.transparent,
                                child: RandomAvatar(
                                  localpart(inviterId),
                                  height: 50,
                                  width: 50,
                                ),
                              ),
                            ),
                            title: Text(
                              '@${inviterId.split(":").first.replaceFirst("@", "")}',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: 4),
                                Text(
                                  isDirectInvite
                                      ? 'Wants to connect with you'
                                      : 'Invited you to join "${displayGroupName}"',
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withOpacity(0.7),
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDirectInvite 
                                        ? Colors.blue.withOpacity(0.1)
                                        : Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isDirectInvite ? Icons.person_add : Icons.group_add,
                                        size: 14,
                                        color: isDirectInvite ? Colors.blue : Colors.green,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        isDirectInvite ? 'Friend Request' : 'Group Invite',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDirectInvite ? Colors.blue : Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              color: colorScheme.onSurface.withOpacity(0.4),
                              size: 16,
                            ),
                            onTap: () {
                              handleInviteTap(
                                context,
                                roomId,
                                roomName,
                                inviterId,
                                isDirectInvite,
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),

            // Close Button
            Container(
              padding: EdgeInsets.all(24),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.primary.withOpacity(0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.4),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 22,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Close',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  });
  }
}
