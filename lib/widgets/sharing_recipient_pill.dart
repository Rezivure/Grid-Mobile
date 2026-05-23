import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_state.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_state.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/services/sharing_state_notifier.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';

/// Top-of-map pill showing how many recipients are currently receiving the
/// local user's location. Reactive to: per-target sharing prefs changes,
/// contacts/groups bloc emissions, the paused state, and time-of-day window
/// transitions (re-checked every 30s when any target has scheduled windows).
class SharingRecipientPill extends StatefulWidget {
  const SharingRecipientPill({super.key});

  @override
  State<SharingRecipientPill> createState() => _SharingRecipientPillState();
}

class _SharingRecipientPillState extends State<SharingRecipientPill> {
  int _count = 0;
  bool _hasScheduledWindows = false;
  Timer? _windowTicker;
  int _recomputeSeq = 0;

  SharingPreferencesRepository? _prefsRepo;
  UserService? _userService;
  ContactsBloc? _contactsBloc;
  GroupsBloc? _groupsBloc;
  StreamSubscription<ContactsState>? _contactsSub;
  StreamSubscription<GroupsState>? _groupsSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = context.read<SharingPreferencesRepository>();
    final user = context.read<UserService>();
    final contacts = context.read<ContactsBloc>();
    final groups = context.read<GroupsBloc>();

    if (repo != _prefsRepo) {
      _prefsRepo?.removeListener(_recompute);
      _prefsRepo = repo;
      _prefsRepo!.addListener(_recompute);
    }
    _userService = user;

    if (contacts != _contactsBloc) {
      _contactsSub?.cancel();
      _contactsBloc = contacts;
      _contactsSub = contacts.stream.listen((_) => _recompute());
    }
    if (groups != _groupsBloc) {
      _groupsSub?.cancel();
      _groupsBloc = groups;
      _groupsSub = groups.stream.listen((_) => _recompute());
    }

    _recompute();
  }

  @override
  void dispose() {
    _prefsRepo?.removeListener(_recompute);
    _contactsSub?.cancel();
    _groupsSub?.cancel();
    _windowTicker?.cancel();
    super.dispose();
  }

  void _ensureWindowTicker() {
    if (_hasScheduledWindows && _windowTicker == null) {
      _windowTicker = Timer.periodic(const Duration(seconds: 30), (_) => _recompute());
    } else if (!_hasScheduledWindows && _windowTicker != null) {
      _windowTicker?.cancel();
      _windowTicker = null;
    }
  }

  Future<void> _recompute() async {
    final repo = _prefsRepo;
    final user = _userService;
    final contactsBloc = _contactsBloc;
    final groupsBloc = _groupsBloc;
    if (repo == null || user == null || contactsBloc == null || groupsBloc == null) return;

    final seq = ++_recomputeSeq;

    List<ContactDisplay> contacts = const [];
    final cState = contactsBloc.state;
    if (cState is ContactsLoaded) contacts = cState.contacts;

    List<Room> groups = const [];
    final gState = groupsBloc.state;
    if (gState is GroupsLoaded) groups = gState.groups;

    String? myUserId;
    try {
      myUserId = await user.getMyUserId();
    } catch (_) {}

    final recipients = <String>{};
    bool anyScheduled = false;

    for (final c in contacts) {
      final status = c.membershipStatus;
      if (status != null && status != 'join') continue;
      if (c.userId == myUserId) continue;
      final prefs = await repo.getSharingPreferences(c.userId, 'user') ??
          await repo.getSharingPreferences(c.userId, 'contact');
      if (prefs != null && !prefs.activeSharing) {
        anyScheduled = true;
      }
      if (await user.isInSharingWindow(c.userId)) {
        recipients.add(c.userId);
      }
    }

    for (final g in groups) {
      if (!g.isGroup) continue;
      final prefs = await repo.getSharingPreferences(g.roomId, 'group');
      if (prefs != null && !prefs.activeSharing) {
        anyScheduled = true;
      }
      if (!await user.isGroupInSharingWindow(g.roomId)) continue;
      for (final memberId in g.members) {
        if (memberId == myUserId) continue;
        recipients.add(memberId);
      }
    }

    if (!mounted || seq != _recomputeSeq) return;
    setState(() {
      _count = recipients.length;
      _hasScheduledWindows = anyScheduled;
    });
    _ensureWindowTicker();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SharingStateNotifier>(
      builder: (context, sharingState, _) {
        final paused = sharingState.isPaused;
        final dotColor = paused ? context.gridColors.paused : context.gridColors.mint;
        final textColor = paused ? context.gridColors.paused : context.gridColors.text;
        final String label;
        if (paused) {
          label = 'SHARING PAUSED';
        } else {
          label = 'SHARING WITH $_count';
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: context.gridColors.surface.withOpacity(0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.gridColors.hairlineStrong),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: paused
                      ? null
                      : [
                          BoxShadow(
                            color: context.gridColors.mint.withOpacity(0.55),
                            blurRadius: 6,
                          ),
                        ],
                ),
              ),
              const SizedBox(width: 7),
              GridMono(
                label,
                color: textColor,
                size: 10.5,
                letterSpacing: 0.1,
                weight: FontWeight.w600,
              ),
            ],
          ),
        );
      },
    );
  }
}
