import 'package:flutter/material.dart';

import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/widgets/friend_request_modal.dart';
import 'package:grid_frontend/widgets/group_invitation_modal.dart';
import 'package:grid_frontend/blocs/invitations/invitations_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_state.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_segmented.dart';

class InvitesModal extends StatefulWidget {
  final RoomService roomService;
  final Future<void> Function() onInviteHandled;

  InvitesModal({required this.onInviteHandled, required this.roomService});

  @override
  _InvitesModalState createState() => _InvitesModalState();
}

/// Inline (non-modal) version of the invites list used as the third
/// subscreen in the map sheet's segmented control. Renders only the
/// list + empty state — the outer sheet supplies the scroll controller
/// and any chrome (handle bar, header).
class InvitesSubscreen extends StatefulWidget {
  const InvitesSubscreen({
    super.key,
    required this.scrollController,
    required this.roomService,
    required this.onInviteHandled,
  });

  final ScrollController scrollController;
  final RoomService roomService;
  final Future<void> Function() onInviteHandled;

  @override
  State<InvitesSubscreen> createState() => _InvitesSubscreenState();
}

class _InvitesSubscreenState extends State<InvitesSubscreen> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InvitationsBloc, InvitationsState>(
      buildWhen: (_, __) => true,
      builder: (context, state) {
        final invites = state is InvitationsLoaded ? state.invitations : [];

        if (invites.isEmpty) {
          return ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(vertical: 48),
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: context.gridColors.mintFaint,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.mail_outline_rounded,
                          color: context.gridColors.mint,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Inbox is quiet.',
                        style: TextStyle(
                          fontFamily: GridTokens.fontUi,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.015,
                          color: context.gridColors.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'New friend requests and group invites land here first.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: GridTokens.fontUi,
                          fontSize: 13,
                          height: 1.45,
                          color: context.gridColors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return _buildInvitesList(
          context: context,
          invites: invites,
          handleInviteTap: (ctx, roomId, roomName, inviterId, isDirect) {
            _routeInviteTap(
              context: ctx,
              roomId: roomId,
              roomName: roomName,
              inviterId: inviterId,
              isDirectInvite: isDirect,
              roomService: widget.roomService,
              onInviteHandled: widget.onInviteHandled,
              onRefresh: () {
                if (mounted) setState(() {});
              },
            );
          },
          scrollController: widget.scrollController,
          roomService: widget.roomService,
          onInviteHandled: widget.onInviteHandled,
          onRefresh: () {
            if (mounted) setState(() {});
          },
        );
      },
    );
  }
}

void _routeInviteTap({
  required BuildContext context,
  required String roomId,
  required String roomName,
  required String inviterId,
  required bool isDirectInvite,
  required RoomService roomService,
  required Future<void> Function() onInviteHandled,
  required VoidCallback onRefresh,
}) {
  if (isDirectInvite) {
    final displayName =
        inviterId.split(':').first.replaceFirst('@', '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FriendRequestModal(
        userId: inviterId,
        displayName: displayName,
        roomId: roomId,
        roomService: roomService,
        onResponse: () async {
          onRefresh();
          await onInviteHandled();
        },
      ),
    );
  } else {
    int expiration = -1;
    String groupName = 'Unnamed Group';
    final parts = roomName.split(':');
    if (parts.length > 3) {
      expiration = int.tryParse(parts[2]) ?? -1;
      groupName = parts[3];
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupInvitationModal(
        roomId: roomId,
        groupName: groupName,
        inviter: inviterId,
        expiration: expiration,
        roomService: roomService,
        refreshCallback: () async {
          onRefresh();
          await onInviteHandled();
        },
      ),
    );
  }
}

Widget _buildInvitesList({
  required BuildContext context,
  required List<dynamic> invites,
  required void Function(
    BuildContext context,
    String roomId,
    String roomName,
    String inviterId,
    bool isDirectInvite,
  ) handleInviteTap,
  required ScrollController? scrollController,
  required RoomService roomService,
  required Future<void> Function() onInviteHandled,
  required VoidCallback onRefresh,
}) {
  final directInvites = <Map<String, dynamic>>[];
  final groupInvites = <Map<String, dynamic>>[];
  final expiredGroupInvites = <Map<String, dynamic>>[];
  final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  for (final raw in invites) {
    final invite = Map<String, dynamic>.from(raw as Map);
    final roomName = (invite['roomName'] as String?) ?? 'Unnamed Room';
    if (roomName.startsWith('Grid:Direct')) {
      directInvites.add(invite);
    } else {
      final parts = roomName.split(':');
      int expiration = -1;
      if (parts.length > 3) {
        expiration = int.tryParse(parts[2]) ?? -1;
      }
      if (expiration != -1 && expiration <= nowEpoch) {
        expiredGroupInvites.add(invite);
      } else {
        groupInvites.add(invite);
      }
    }
  }

  final Object? featuredId =
      invites.isNotEmpty ? (invites.first as Map)['roomId'] : null;
  final children = <Widget>[];

  if (directInvites.isNotEmpty) {
    children.add(const GridSectionHeader(text: 'FROM PEOPLE'));
    for (final invite in directInvites) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: _PersonInviteCard(
          invite: invite,
          featured: invite['roomId'] == featuredId,
          onAccept: () => handleInviteTap(
            context,
            (invite['roomId'] as String?) ?? 'Unknown',
            (invite['roomName'] as String?) ?? 'Unnamed Room',
            (invite['inviter'] as String?) ?? 'Unknown',
            true,
          ),
          onDecline: () => handleInviteTap(
            context,
            (invite['roomId'] as String?) ?? 'Unknown',
            (invite['roomName'] as String?) ?? 'Unnamed Room',
            (invite['inviter'] as String?) ?? 'Unknown',
            true,
          ),
        ),
      ));
    }
  }

  if (groupInvites.isNotEmpty) {
    children.add(const GridSectionHeader(text: 'GROUP INVITES'));
    for (final invite in groupInvites) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: _GroupInviteCard(
          invite: invite,
          featured: invite['roomId'] == featuredId,
          onJoin: () => handleInviteTap(
            context,
            (invite['roomId'] as String?) ?? 'Unknown',
            (invite['roomName'] as String?) ?? 'Unnamed Room',
            (invite['inviter'] as String?) ?? 'Unknown',
            false,
          ),
          onDismiss: () => handleInviteTap(
            context,
            (invite['roomId'] as String?) ?? 'Unknown',
            (invite['roomName'] as String?) ?? 'Unnamed Room',
            (invite['inviter'] as String?) ?? 'Unknown',
            false,
          ),
        ),
      ));
    }
  }

  if (expiredGroupInvites.isNotEmpty) {
    children.add(const GridSectionHeader(text: 'EXPIRED'));
    for (final invite in expiredGroupInvites) {
      final roomId = (invite['roomId'] as String?) ?? 'Unknown';
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: _ExpiredInviteCard(
          invite: invite,
          onRemove: () async {
            final ok = await roomService.leaveRoom(roomId);
            if (ok) {
              InAppNotifier.instance.show(
                title: 'Expired invite removed',
                variant: InAppNotificationVariant.success,
              );
            } else {
              InAppNotifier.instance.show(
                title: 'Could not remove invite',
                message: 'Try again.',
                variant: InAppNotificationVariant.error,
              );
            }
            await onInviteHandled();
            onRefresh();
          },
        ),
      ));
    }
  }

  return ListView(
    controller: scrollController,
    padding: const EdgeInsets.only(top: 8, bottom: 24),
    children: children,
  );
}

class _InvitesModalState extends State<InvitesModal> {

  @override
  Widget build(BuildContext context) {
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
          color: context.gridColors.bg,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(GridTokens.r2Xl),
            topRight: Radius.circular(GridTokens.r2Xl),
          ),
        ),
        child: Column(
          children: [
            // Handle indicator
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.gridColors.hairlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header Section
            Container(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Invites',
                    style: TextStyle(
                      fontFamily: GridTokens.fontUi,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.01,
                      color: context.gridColors.text,
                    ),
                  ),
                  if (invites.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    GridMono(
                      '${invites.length} pending',
                      color: context.gridColors.text3,
                      size: 11,
                      letterSpacing: 0.08,
                    ),
                  ],
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
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: context.gridColors.mintFaint,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Icon(
                                Icons.mail_outline_rounded,
                                color: context.gridColors.mint,
                                size: 40,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Inbox is quiet.',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.02,
                                color: context.gridColors.text,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'When someone wants to share their location with you, it\'ll land here first. You decide what happens next.',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: context.gridColors.text2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildInvitesList(
                      context: context,
                      invites: invites,
                      handleInviteTap: handleInviteTap,
                    ),
            ),

            // Close Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: GridButton(
                label: 'Close',
                style: GridButtonStyle.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  });
  }

  // Builds the sectioned "From people" / "Group invites" list.
  Widget _buildInvitesList({
    required BuildContext context,
    required List<dynamic> invites,
    required void Function(
      BuildContext context,
      String roomId,
      String roomName,
      String inviterId,
      bool isDirectInvite,
    ) handleInviteTap,
  }) {
    final directInvites = <Map<String, dynamic>>[];
    final groupInvites = <Map<String, dynamic>>[];
    final expiredGroupInvites = <Map<String, dynamic>>[];
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final raw in invites) {
      final invite = Map<String, dynamic>.from(raw as Map);
      final roomName = (invite['roomName'] as String?) ?? 'Unnamed Room';
      if (roomName.startsWith('Grid:Direct')) {
        directInvites.add(invite);
      } else {
        // Mirror _GroupInviteCard.build parsing: expiration sits at index 2 of
        // a colon-split roomName when the group invite includes one.
        final parts = roomName.split(':');
        int expiration = -1;
        if (parts.length > 3) {
          expiration = int.tryParse(parts[2]) ?? -1;
        }
        // expiration of -1 means "permanent"; anything else that's already
        // <= now is dead and belongs in the EXPIRED bucket.
        if (expiration != -1 && expiration <= nowEpoch) {
          expiredGroupInvites.add(invite);
        } else {
          groupInvites.add(invite);
        }
      }
    }

    // Featured (mint-faint backing) goes on the first invite, regardless of
    // section — matches the §5.17 "most recent" rule.
    final Object? featuredId = invites.isNotEmpty
        ? (invites.first as Map)['roomId']
        : null;

    final children = <Widget>[];

    if (directInvites.isNotEmpty) {
      children.add(const GridSectionHeader(text: 'FROM PEOPLE'));
      for (final invite in directInvites) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _PersonInviteCard(
              invite: invite,
              featured: invite['roomId'] == featuredId,
              onAccept: () => handleInviteTap(
                context,
                (invite['roomId'] as String?) ?? 'Unknown',
                (invite['roomName'] as String?) ?? 'Unnamed Room',
                (invite['inviter'] as String?) ?? 'Unknown',
                true,
              ),
              onDecline: () => handleInviteTap(
                context,
                (invite['roomId'] as String?) ?? 'Unknown',
                (invite['roomName'] as String?) ?? 'Unnamed Room',
                (invite['inviter'] as String?) ?? 'Unknown',
                true,
              ),
            ),
          ),
        );
      }
    }

    if (groupInvites.isNotEmpty) {
      children.add(const GridSectionHeader(text: 'GROUP INVITES'));
      for (final invite in groupInvites) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _GroupInviteCard(
              invite: invite,
              featured: invite['roomId'] == featuredId,
              onJoin: () => handleInviteTap(
                context,
                (invite['roomId'] as String?) ?? 'Unknown',
                (invite['roomName'] as String?) ?? 'Unnamed Room',
                (invite['inviter'] as String?) ?? 'Unknown',
                false,
              ),
              onDismiss: () => handleInviteTap(
                context,
                (invite['roomId'] as String?) ?? 'Unknown',
                (invite['roomName'] as String?) ?? 'Unnamed Room',
                (invite['inviter'] as String?) ?? 'Unknown',
                false,
              ),
            ),
          ),
        );
      }
    }

    if (expiredGroupInvites.isNotEmpty) {
      children.add(const GridSectionHeader(text: 'EXPIRED'));
      for (final invite in expiredGroupInvites) {
        final roomId = (invite['roomId'] as String?) ?? 'Unknown';
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _ExpiredInviteCard(
              invite: invite,
              onRemove: () => _dismissExpiredInvite(context, roomId),
            ),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: children,
    );
  }

  Future<void> _dismissExpiredInvite(
    BuildContext context,
    String roomId,
  ) async {
    final ok = await widget.roomService.leaveRoom(roomId);
    if (!mounted) return;
    if (ok) {
      InAppNotifier.instance.show(
        title: 'Expired invite removed',
        variant: InAppNotificationVariant.success,
      );
    } else {
      InAppNotifier.instance.show(
        title: 'Could not remove invite',
        message: 'Try again.',
        variant: InAppNotificationVariant.error,
      );
    }
    await widget.onInviteHandled();
    if (mounted) setState(() {});
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Invite cards
// ─────────────────────────────────────────────────────────────────────────

class _PersonInviteCard extends StatelessWidget {
  const _PersonInviteCard({
    required this.invite,
    required this.featured,
    required this.onAccept,
    required this.onDecline,
  });

  final Map<String, dynamic> invite;
  final bool featured;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final inviterId = (invite['inviter'] as String?) ?? 'Unknown';
    final handle = localpart(inviterId);
    // Use the localpart as a friendly display name when no profile is known.
    final displayName = handle.isEmpty
        ? 'Unknown'
        : (handle[0].toUpperCase() + handle.substring(1));

    return _InviteShell(
      featured: featured,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridAvatar(name: handle, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GridTokens.fontUi,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: context.gridColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    GridMono(
                      '@$handle',
                      uppercase: false,
                      size: 11,
                      letterSpacing: 0.04,
                      color: context.gridColors.text3,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Wants to share location with you',
            style: TextStyle(
              fontFamily: GridTokens.fontUi,
              fontSize: 13,
              height: 1.4,
              color: context.gridColors.text2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GridButton(
                  label: 'Accept',
                  icon: Icons.check_rounded,
                  height: 44,
                  onPressed: onAccept,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GridButton(
                  label: 'Decline',
                  style: GridButtonStyle.secondary,
                  height: 44,
                  onPressed: onDecline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupInviteCard extends StatelessWidget {
  const _GroupInviteCard({
    required this.invite,
    required this.featured,
    required this.onJoin,
    required this.onDismiss,
  });

  final Map<String, dynamic> invite;
  final bool featured;
  final VoidCallback onJoin;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final inviterId = (invite['inviter'] as String?) ?? 'Unknown';
    final roomName = (invite['roomName'] as String?) ?? 'Unnamed Room';
    final inviterHandle = localpart(inviterId);
    final inviterDisplay = inviterHandle.isEmpty
        ? 'Someone'
        : (inviterHandle[0].toUpperCase() + inviterHandle.substring(1));

    String groupName = 'Unnamed Group';
    int expiration = -1;
    final parts = roomName.split(':');
    if (parts.length > 3) {
      expiration = int.tryParse(parts[2]) ?? -1;
      groupName = parts[3];
    } else {
      groupName = roomName;
    }

    final expiry = _formatExpiry(expiration);

    return _InviteShell(
      featured: featured,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StackedAvatars(seeds: [inviterHandle, groupName, roomName]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GridTokens.fontUi,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: context.gridColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$inviterDisplay invited you',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GridTokens.fontUi,
                        fontSize: 13,
                        color: context.gridColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 13,
                color: context.gridColors.amber,
              ),
              const SizedBox(width: 6),
              GridMono(
                expiration == -1 ? 'permanent invite' : 'auto-ends in $expiry',
                uppercase: false,
                size: 11,
                letterSpacing: 0.04,
                color: context.gridColors.amber,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GridButton(
                  label: 'Join group',
                  icon: Icons.group_add_rounded,
                  height: 44,
                  onPressed: onJoin,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GridButton(
                  label: 'Dismiss',
                  style: GridButtonStyle.secondary,
                  height: 44,
                  onPressed: onDismiss,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatExpiry(int expiration) {
    if (expiration == -1) return 'permanent';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = expiration - now;
    if (diff <= 0) return 'expired';
    final minutes = (diff / 60).round();
    final hours = (minutes / 60).round();
    final days = (hours / 24).round();
    if (days > 0) return '$days day${days > 1 ? 's' : ''}';
    if (hours > 0) return '$hours hour${hours > 1 ? 's' : ''}';
    if (minutes > 0) return '$minutes min';
    return 'a few seconds';
  }
}

/// Shared card chrome — surface bg, hairline border, rounded-16. When
/// [featured], adds a subtle mint-faint gradient backing per §5.17.
class _InviteShell extends StatelessWidget {
  const _InviteShell({required this.child, required this.featured});

  final Widget child;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: featured
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.gridColors.mintFaint, context.gridColors.surface],
              )
            : null,
        color: featured ? null : context.gridColors.surface,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(
          color: featured ? context.gridColors.mintSoft : context.gridColors.hairline,
          width: 1,
        ),
      ),
      child: child,
    );
  }
}

/// Card for an expired group invite — mirrors `_GroupInviteCard` so the user
/// sees the same info (avatars, group name, inviter), but the Join path is
/// replaced with a single Remove action that drops them from the dead room.
class _ExpiredInviteCard extends StatelessWidget {
  const _ExpiredInviteCard({
    required this.invite,
    required this.onRemove,
  });

  final Map<String, dynamic> invite;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final inviterId = (invite['inviter'] as String?) ?? 'Unknown';
    final roomName = (invite['roomName'] as String?) ?? 'Unnamed Room';
    final inviterHandle = localpart(inviterId);
    final inviterDisplay = inviterHandle.isEmpty
        ? 'Someone'
        : (inviterHandle[0].toUpperCase() + inviterHandle.substring(1));

    String groupName = 'Unnamed Group';
    final parts = roomName.split(':');
    if (parts.length > 3) {
      groupName = parts[3];
    } else {
      groupName = roomName;
    }

    return _InviteShell(
      featured: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StackedAvatars(seeds: [inviterHandle, groupName, roomName]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GridTokens.fontUi,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: context.gridColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$inviterDisplay invited you',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GridTokens.fontUi,
                        fontSize: 13,
                        color: context.gridColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _DismissXButton(onTap: onRemove),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 13,
                color: context.gridColors.danger,
              ),
              const SizedBox(width: 6),
              GridMono(
                'expired',
                uppercase: false,
                size: 11,
                letterSpacing: 0.04,
                color: context.gridColors.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 28×28 inline X used in the corner of an expired invite card to
/// drop the user from the dead matrix room.
class _DismissXButton extends StatelessWidget {
  const _DismissXButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rSm),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: context.gridColors.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rSm),
            border: Border.all(color: context.gridColors.hairline),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: context.gridColors.text3,
          ),
        ),
      ),
    );
  }
}

/// Three overlapping mini-avatars for group invites.
class _StackedAvatars extends StatelessWidget {
  const _StackedAvatars({required this.seeds});

  final List<String> seeds;

  static const double _size = 28;
  static const double _overlap = 10;

  @override
  Widget build(BuildContext context) {
    final visible = seeds.where((s) => s.isNotEmpty).take(3).toList();
    if (visible.isEmpty) {
      return const SizedBox(width: _size, height: _size);
    }
    const tile = _size + 4;
    final width = tile + (visible.length - 1) * (tile - _overlap);
    return SizedBox(
      width: width,
      height: tile,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < visible.length; i++)
            Positioned(
              left: i * (tile - _overlap),
              top: 0,
              child: GridAvatar(
                name: visible[i],
                size: _size,
                padding: 2,
              ),
            ),
        ],
      ),
    );
  }
}
