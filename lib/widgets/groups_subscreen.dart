// lib/widgets/groups_subscreen.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';
import 'package:grid_frontend/blocs/groups/groups_state.dart';
import 'package:grid_frontend/models/room.dart' as gr;
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_status_pill.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';

/// Bottom-sheet body that lists the user's real groups (driven by
/// `GroupsBloc`) using the Grid redesign card pattern.
///
/// Selecting a group hands the `Room` up to the parent scroll window via
/// [onGroupSelected]; the parent owns navigation to `GroupDetailsSubscreen`.
class GroupsSubscreen extends StatefulWidget {
  final ScrollController scrollController;
  final void Function(gr.Room room)? onGroupSelected;

  const GroupsSubscreen({
    super.key,
    required this.scrollController,
    this.onGroupSelected,
  });

  @override
  State<GroupsSubscreen> createState() => _GroupsSubscreenState();
}

class _GroupsSubscreenState extends State<GroupsSubscreen> {
  @override
  void initState() {
    super.initState();
    // Make sure the BLoC has up-to-date data.
    context.read<GroupsBloc>().add(LoadGroups());
  }

  /// "Grid:Group:<expiration>:<name>:<creator>" → human group name.
  String _parseGroupName(gr.Room room) {
    final parts = room.name.split(':');
    if (parts.length > 3) return parts[3];
    return room.name;
  }

  String _placeFor(gr.Room room) => '${room.members.length} members';

  /// Returns a non-null timer label only when the group has an expiry.
  String? _timerFor(gr.Room room) {
    if (room.expirationTimestamp == 0) return null;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remaining = room.expirationTimestamp - now;
    if (remaining <= 0) return 'expired';
    final hours = remaining ~/ 3600;
    final minutes = (remaining % 3600) ~/ 60;
    final days = hours ~/ 24;
    if (days > 0) return 'ends in ${days}d ${hours % 24}h';
    if (hours > 0) return 'ends in ${hours}h ${minutes}m';
    return 'ends in ${minutes}m';
  }

  /// Crude "is this a trip" heuristic — long-running, named like a trip.
  bool _isTripGroup(gr.Room room) {
    final lower = _parseGroupName(room).toLowerCase();
    return lower.contains('trip') ||
        lower.contains('road') ||
        lower.contains('vacation');
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GroupsBloc, GroupsState>(
      builder: (context, state) {
        if (state is GroupsLoading || state is GroupsInitial) {
          return const Center(
            child: CircularProgressIndicator(color: GridTokens.mint),
          );
        }
        if (state is GroupsError) {
          return _errorState(state.message);
        }

        final groups = state is GroupsLoaded ? state.groups : <gr.Room>[];

        if (groups.isEmpty) {
          return _emptyState();
        }

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final room = groups[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GroupCard(
                name: _parseGroupName(room),
                memberIds: room.members,
                memberCount: room.members.length,
                place: _placeFor(room),
                timerLabel: _timerFor(room),
                isTrip: _isTripGroup(room),
                featured: index == 0,
                onTap: () => widget.onGroupSelected?.call(room),
              ),
            );
          },
        );
      },
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: GridTokens.mintFaint,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.group_outlined,
              color: GridTokens.mint,
              size: 40,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No groups yet.',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.02,
              color: GridTokens.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a group to share location with several people at once — perfect for trips, families, or close friends.',
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: GridTokens.text2,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: GridTokens.danger,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            'Couldn\'t load groups.',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: GridTokens.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 12.5,
              color: GridTokens.text2,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          GridButton(
            label: 'Try again',
            expand: false,
            style: GridButtonStyle.secondary,
            onPressed: () => context.read<GroupsBloc>().add(LoadGroups()),
          ),
        ],
      ),
    );
  }
}

/// Card view for one real group.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.name,
    required this.memberIds,
    required this.memberCount,
    required this.place,
    required this.timerLabel,
    required this.isTrip,
    required this.featured,
    required this.onTap,
  });

  final String name;
  final List<String> memberIds;
  final int memberCount;
  final String place;
  final String? timerLabel;
  final bool isTrip;
  final bool featured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      gradient: featured
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [GridTokens.mintFaint, GridTokens.surface],
            )
          : null,
      color: featured ? null : GridTokens.surface,
      borderRadius: BorderRadius.circular(GridTokens.rLg),
      border: Border.all(
        color: featured ? GridTokens.mintSoft : GridTokens.hairline,
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        child: Ink(
          decoration: decoration,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StackedAvatars(names: memberIds),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.getFont(
                                    'Geist',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.01,
                                    color: GridTokens.text,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              if (isTrip) ...[
                                const SizedBox(width: 8),
                                const GridStatusPill(
                                  label: 'TRIP',
                                  kind: GridStatusKind.trip,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$memberCount members  ·  $place',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.01,
                              color: GridTokens.text2,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (timerLabel != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: GridTokens.surface2,
                      borderRadius: BorderRadius.circular(GridTokens.rMd),
                      border: Border.all(color: GridTokens.hairline),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 14,
                          color: GridTokens.text3,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GridMono(
                            timerLabel!,
                            color: GridTokens.text2,
                            size: 11,
                            letterSpacing: 0.06,
                            uppercase: false,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to 4 avatars overlapped left-to-right with a bg ring around each.
class _StackedAvatars extends StatelessWidget {
  const _StackedAvatars({required this.names});

  final List<String> names;

  static const double _avatarSize = 32;
  static const double _overlap = 12;

  @override
  Widget build(BuildContext context) {
    final visible = names.take(4).toList();
    if (visible.isEmpty) {
      return const SizedBox(width: _avatarSize, height: _avatarSize);
    }

    const tile = _avatarSize + 6;
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
                size: _avatarSize,
                padding: 3,
              ),
            ),
        ],
      ),
    );
  }
}
