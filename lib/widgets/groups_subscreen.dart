// lib/widgets/groups_subscreen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';
import 'package:grid_frontend/blocs/groups/groups_state.dart';
import 'package:grid_frontend/models/room.dart' as gr;
import 'package:grid_frontend/models/sharing_preferences.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/services/sharing_state_notifier.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_status_pill.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_segmented.dart';
import 'package:grid_frontend/widgets/grid/sharing_row_state.dart';

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
  final Map<String, SharingRowState> _sharingState = {};
  bool _hasScheduledWindows = false;
  Timer? _windowTicker;
  int _sharingRecomputeSeq = 0;
  SharingPreferencesRepository? _prefsRepo;
  UserService? _userService;

  @override
  void initState() {
    super.initState();
    // Make sure the BLoC has up-to-date data.
    context.read<GroupsBloc>().add(LoadGroups());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = context.read<SharingPreferencesRepository>();
    final user = context.read<UserService>();
    if (repo != _prefsRepo) {
      _prefsRepo?.removeListener(_recomputeSharing);
      _prefsRepo = repo;
      _prefsRepo!.addListener(_recomputeSharing);
    }
    _userService = user;
    _recomputeSharing();
  }

  @override
  void dispose() {
    _windowTicker?.cancel();
    _prefsRepo?.removeListener(_recomputeSharing);
    super.dispose();
  }

  void _ensureWindowTicker() {
    if (_hasScheduledWindows && _windowTicker == null) {
      _windowTicker =
          Timer.periodic(const Duration(seconds: 30), (_) => _recomputeSharing());
    } else if (!_hasScheduledWindows && _windowTicker != null) {
      _windowTicker?.cancel();
      _windowTicker = null;
    }
  }

  Future<void> _recomputeSharing() async {
    final repo = _prefsRepo;
    final user = _userService;
    if (repo == null || user == null) return;
    final state = context.read<GroupsBloc>().state;
    if (state is! GroupsLoaded) return;
    final seq = ++_sharingRecomputeSeq;
    final globallyPaused =
        context.read<SharingStateNotifier>().isPaused;
    final next = <String, SharingRowState>{};
    bool anyScheduled = false;
    final targets = state.groups.where((g) => g.isGroup).toList();
    final results = await Future.wait(targets.map((g) async {
      final inWindowF = user.isGroupInSharingWindow(g.roomId);
      final prefsF = repo.getSharingPreferences(g.roomId, 'group');
      final inWindow = await inWindowF;
      final prefs = await prefsF;
      return _GroupSharingResult(g.roomId, inWindow, prefs);
    }));
    for (final r in results) {
      if (r.prefs != null && !r.prefs!.activeSharing) anyScheduled = true;
      if (globallyPaused) {
        next[r.roomId] = SharingRowState.off;
      } else if (r.inWindow) {
        next[r.roomId] = SharingRowState.active;
      } else {
        final hasScheduled = r.prefs?.shareWindows
                    ?.any((w) => w.isActive == true) ==
                true &&
            r.prefs?.activeSharing == false;
        next[r.roomId] = hasScheduled
            ? SharingRowState.scheduledOut
            : SharingRowState.off;
      }
    }
    if (!mounted || seq != _sharingRecomputeSeq) return;
    setState(() {
      _sharingState
        ..clear()
        ..addAll(next);
      _hasScheduledWindows = anyScheduled;
    });
    _ensureWindowTicker();
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
    return BlocConsumer<GroupsBloc, GroupsState>(
      listener: (context, state) {
        if (state is GroupsLoaded) _recomputeSharing();
      },
      builder: (context, state) {
        if (state is GroupsLoading || state is GroupsInitial) {
          return Center(
            child: CircularProgressIndicator(color: context.gridColors.mint),
          );
        }
        if (state is GroupsError) {
          return _errorState(state.message);
        }

        final groups = state is GroupsLoaded ? state.groups : <gr.Room>[];

        if (groups.isEmpty) {
          return _emptyState();
        }

        return Consumer<SharingStateNotifier>(
          builder: (context, sharingState, _) {
            final globallyPaused = sharingState.isPaused;
            return ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: groups.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return GridSectionHeader(
                    text: 'MY GROUPS',
                    trailing: GridMono(
                      '${groups.length}',
                      color: context.gridColors.text3,
                      size: 10.5,
                      letterSpacing: 0.08,
                    ),
                  );
                }
                final groupIndex = index - 1;
                final room = groups[groupIndex];
                final stored =
                    _sharingState[room.roomId] ?? SharingRowState.active;
                final sharingState = globallyPaused
                    ? SharingRowState.off
                    : stored;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    0,
                    14,
                    groupIndex == groups.length - 1 ? 0 : 12,
                  ),
                  child: _GroupCard(
                    name: _parseGroupName(room),
                    memberIds: room.members,
                    memberCount: room.members.length,
                    place: _placeFor(room),
                    timerLabel: _timerFor(room),
                    isTrip: _isTripGroup(room),
                    featured: groupIndex == 0,
                    sharingState: sharingState,
                    onTap: () => widget.onGroupSelected?.call(room),
                  ),
                );
              },
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
              color: context.gridColors.mintFaint,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.group_outlined,
              color: context.gridColors.mint,
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
              color: context.gridColors.text,
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
              color: context.gridColors.text2,
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
          Icon(
            Icons.error_outline_rounded,
            color: context.gridColors.danger,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            'Couldn\'t load groups.',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.gridColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 12.5,
              color: context.gridColors.text2,
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
    this.sharingState = SharingRowState.active,
  });

  final String name;
  final List<String> memberIds;
  final int memberCount;
  final String place;
  final String? timerLabel;
  final bool isTrip;
  final bool featured;
  final VoidCallback onTap;
  final SharingRowState sharingState;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
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
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        child: Ink(
          decoration: decoration,
          child: Opacity(
            opacity: sharingState == SharingRowState.active ? 1.0 : 0.55,
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
                                    color: context.gridColors.text,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              if (sharingState == SharingRowState.scheduledOut) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 12,
                                  color: context.gridColors.text3,
                                ),
                              ],
                              if (sharingState == SharingRowState.off) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.visibility_off_rounded,
                                  size: 12,
                                  color: context.gridColors.text3,
                                ),
                              ],
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
                              color: context.gridColors.text2,
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
                      color: context.gridColors.surface2,
                      borderRadius: BorderRadius.circular(GridTokens.rMd),
                      border: Border.all(color: context.gridColors.hairline),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 14,
                          color: context.gridColors.text3,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GridMono(
                            timerLabel!,
                            color: context.gridColors.text2,
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
                userId: visible[i],
                size: _avatarSize,
                padding: 3,
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupSharingResult {
  _GroupSharingResult(this.roomId, this.inWindow, this.prefs);
  final String roomId;
  final bool inWindow;
  final SharingPreferences? prefs;
}

