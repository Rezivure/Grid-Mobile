import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../services/in_app_notifier.dart';
import '../services/room_service.dart';
import '../styles/grid_colors.dart';
import '../styles/tokens.dart';
import '../utilities/utils.dart' as utils;
import 'grid/grid_avatar.dart';
import 'grid/grid_button.dart';
import 'grid/grid_mono.dart';
import 'grid/grid_sheet.dart';

/// Admin-only group member management. Lets users with sufficient
/// power kick members and promote/demote between member and admin.
class ManageMembersModal extends StatefulWidget {
  const ManageMembersModal({
    super.key,
    required this.roomId,
    required this.roomService,
  });

  final String roomId;
  final RoomService roomService;

  @override
  State<ManageMembersModal> createState() => _ManageMembersModalState();
}

class _ManageMembersModalState extends State<ManageMembersModal> {
  late final String _myId;
  List<_MemberEntry> _members = const [];
  bool _canKick = false;
  bool _canChangePower = false;

  @override
  void initState() {
    super.initState();
    _myId = widget.roomService.client.userID ?? '';
    _refresh();
  }

  void _refresh() {
    final room = widget.roomService.client.getRoomById(widget.roomId);
    if (room == null) {
      setState(() {
        _members = const [];
        _canKick = false;
        _canChangePower = false;
      });
      return;
    }
    final joined = room
        .getParticipants()
        .where((p) => p.membership == Membership.join)
        .toList();
    final entries = joined.map((p) {
      final pl = room.getPowerLevelByUserId(p.id);
      final display = (p.displayName ?? '').trim().isNotEmpty
          ? p.displayName!.trim()
          : utils.formatUserId(p.id);
      return _MemberEntry(
        userId: p.id,
        displayName: display,
        powerLevel: pl,
      );
    }).toList()
      ..sort((a, b) {
        if (a.userId == _myId) return -1;
        if (b.userId == _myId) return 1;
        if (b.powerLevel != a.powerLevel) {
          return b.powerLevel.compareTo(a.powerLevel);
        }
        return a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            );
      });
    setState(() {
      _members = entries;
      _canKick = room.canKick;
      _canChangePower = room.canChangePowerLevel;
    });
  }

  String _firstName(String s) => s.split(' ').first;

  Future<void> _onKick(_MemberEntry m) async {
    final firstName = _firstName(m.displayName);
    final confirmed = await _confirmKick(firstName);
    if (confirmed != true || !mounted) return;

    final snapshot = _members;
    setState(() {
      _members = _members.where((e) => e.userId != m.userId).toList();
    });

    try {
      final room = widget.roomService.client.getRoomById(widget.roomId);
      if (room == null) throw 'Room not found';
      await room.kick(m.userId);
      if (!mounted) return;
      InAppNotifier.instance.show(
        title: 'Removed from group',
        message: '$firstName no longer has access.',
        variant: InAppNotificationVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _members = snapshot);
      InAppNotifier.instance.show(
        title: 'Could not remove member',
        message: '$e',
        variant: InAppNotificationVariant.warning,
      );
    }
  }

  Future<void> _onSetPower(_MemberEntry m, int newPower) async {
    final firstName = _firstName(m.displayName);
    final isPromote = newPower >= 100;
    try {
      final room = widget.roomService.client.getRoomById(widget.roomId);
      if (room == null) throw 'Room not found';
      await room.setPower(m.userId, newPower);
      if (!mounted) return;
      setState(() {
        _members = _members
            .map((e) => e.userId == m.userId
                ? _MemberEntry(
                    userId: e.userId,
                    displayName: e.displayName,
                    powerLevel: newPower,
                  )
                : e)
            .toList();
      });
      InAppNotifier.instance.show(
        title: isPromote ? 'Promoted to admin' : 'Demoted to member',
        message: isPromote
            ? '$firstName can now manage this group.'
            : '$firstName can no longer manage this group.',
        variant: InAppNotificationVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      InAppNotifier.instance.show(
        title: 'Could not update role',
        message: '$e',
        variant: InAppNotificationVariant.warning,
      );
    }
  }

  Future<bool?> _confirmKick(String firstName) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            decoration: BoxDecoration(
              color: context.gridColors.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: context.gridColors.hairline),
            ),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: context.gridColors.dangerSoft,
                        borderRadius: BorderRadius.circular(GridTokens.rSm),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: context.gridColors.danger,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Remove $firstName from group?',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.015,
                          color: context.gridColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "They'll lose access to everyone's location in this group.",
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 13,
                    color: context.gridColors.text2,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: GridButton(
                        label: 'Cancel',
                        style: GridButtonStyle.secondary,
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GridButton(
                        label: 'Remove',
                        style: GridButtonStyle.danger,
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = _members.length;
    return GridSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridSheetHeader(
            title: 'Manage members',
            subtitle:
                '$memberCount member${memberCount == 1 ? '' : 's'}',
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: _members.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No members to manage.',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 13.5,
                          color: context.gridColors.text2,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                    itemCount: _members.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) => _buildRow(_members[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(_MemberEntry m) {
    final isSelf = m.userId == _myId;
    final handle = utils.formatUserId(m.userId);
    final showHandle = handle != m.displayName;
    final canKickThis = _canKick && !isSelf;
    final canChangeThis = _canChangePower && !isSelf;
    final isAdmin = m.powerLevel >= 100;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      decoration: BoxDecoration(
        color: context.gridColors.surface,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: context.gridColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GridAvatar(name: m.displayName, userId: m.userId, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: context.gridColors.text,
                        ),
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(You)',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 12,
                          color: context.gridColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
                if (showHandle) ...[
                  const SizedBox(height: 2),
                  Text(
                    handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 12,
                      color: context.gridColors.text3,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                _powerPill(m.powerLevel),
              ],
            ),
          ),
          if (canKickThis || canChangeThis)
            _trailingActions(m, isAdmin, canChangeThis, canKickThis),
        ],
      ),
    );
  }

  Widget _powerPill(int pl) {
    final c = context.gridColors;
    late final Color fg;
    late final Color bg;
    late final String label;
    if (pl >= 100) {
      fg = c.amber;
      bg = c.amberSoft;
      label = 'Admin';
    } else if (pl >= 50) {
      fg = c.mint;
      bg = c.mintSoft;
      label = 'Moderator';
    } else {
      fg = c.text2;
      bg = c.surface2;
      label = 'Member';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: GridMono(label, color: fg, size: 10, letterSpacing: 0.08),
    );
  }

  Widget _trailingActions(
    _MemberEntry m,
    bool isAdmin,
    bool canChangeThis,
    bool canKickThis,
  ) {
    return PopupMenuButton<String>(
      tooltip: 'Member actions',
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: context.gridColors.text2,
      ),
      color: context.gridColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        side: BorderSide(color: context.gridColors.hairline),
      ),
      onSelected: (v) {
        switch (v) {
          case 'promote':
            _onSetPower(m, 100);
            break;
          case 'demote':
            _onSetPower(m, 0);
            break;
          case 'kick':
            _onKick(m);
            break;
        }
      },
      itemBuilder: (ctx) => [
        if (canChangeThis)
          PopupMenuItem<String>(
            value: isAdmin ? 'demote' : 'promote',
            child: Row(
              children: [
                Icon(
                  isAdmin
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 16,
                  color: context.gridColors.text,
                ),
                const SizedBox(width: 10),
                Text(
                  isAdmin ? 'Demote to member' : 'Promote to admin',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 13.5,
                    color: context.gridColors.text,
                  ),
                ),
              ],
            ),
          ),
        if (canKickThis)
          PopupMenuItem<String>(
            value: 'kick',
            child: Row(
              children: [
                Icon(
                  Icons.person_remove_outlined,
                  size: 16,
                  color: context.gridColors.danger,
                ),
                const SizedBox(width: 10),
                Text(
                  'Remove from group',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 13.5,
                    color: context.gridColors.danger,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MemberEntry {
  const _MemberEntry({
    required this.userId,
    required this.displayName,
    required this.powerLevel,
  });

  final String userId;
  final String displayName;
  final int powerLevel;
}
