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
import 'package:grid_frontend/services/location/location_dispatch.dart';
import 'package:grid_frontend/services/sharing_state_notifier.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';

/// Top-of-map pill showing how many recipients are currently receiving the
/// local user's location. Reactive to: per-target sharing prefs changes,
/// contacts/groups bloc emissions, the paused state, and time-of-day window
/// transitions (re-checked every 30s when any target has scheduled windows).
///
/// On each successful broadcast (via [LocationDispatch.onBroadcast]) it plays
/// a quick two-stage cue: a mint stroke sweeps clockwise around the pill
/// border ("sending"), then the status dot pulses ("sent"). Re-triggers
/// inside the animation window are ignored so rapid posts don't strobe, and
/// it never plays while sharing is paused/incognito.
class SharingRecipientPill extends StatefulWidget {
  const SharingRecipientPill({super.key});

  @override
  State<SharingRecipientPill> createState() => _SharingRecipientPillState();
}

class _SharingRecipientPillState extends State<SharingRecipientPill>
    with SingleTickerProviderStateMixin {
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

  // Broadcast cue. One controller drives both stages: the first ~65% sweeps
  // the border stroke, the tail pulses the dot.
  static const Duration _cueDuration = Duration(milliseconds: 700);
  static const double _sweepEnd = 0.62; // sweep finishes, then dot pulses
  late final AnimationController _cue;
  late final Animation<double> _sweep; // 0→1 border draw
  late final Animation<double> _pulse; // 0→1→0 dot emphasis
  LocationDispatch? _dispatch;
  StreamSubscription<void>? _broadcastSub;

  @override
  void initState() {
    super.initState();
    _cue = AnimationController(vsync: this, duration: _cueDuration);
    _sweep = CurvedAnimation(
      parent: _cue,
      curve: const Interval(0.0, _sweepEnd, curve: Curves.easeInOut),
    );
    _pulse = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 55),
    ]).animate(CurvedAnimation(
      parent: _cue,
      curve: const Interval(_sweepEnd, 1.0, curve: Curves.easeOut),
    ));
  }

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

    final dispatch = context.read<LocationDispatch>();
    if (dispatch != _dispatch) {
      _broadcastSub?.cancel();
      _dispatch = dispatch;
      _broadcastSub = dispatch.onBroadcast.listen((_) => _playCue());
    }

    _recompute();
  }

  @override
  void dispose() {
    _prefsRepo?.removeListener(_recompute);
    _contactsSub?.cancel();
    _groupsSub?.cancel();
    _broadcastSub?.cancel();
    _windowTicker?.cancel();
    _cue.dispose();
    super.dispose();
  }

  // Throttled: ignore re-triggers while a cue is already running.
  void _playCue() {
    if (!mounted) return;
    if (_dispatch != null && _dispatch!.isPaused) return; // guard incognito
    if (_cue.isAnimating) return;
    _cue.forward(from: 0.0);
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
        final mint = context.gridColors.mint;
        final String label;
        if (paused) {
          label = 'SHARING PAUSED';
        } else {
          label = 'SHARING WITH $_count';
        }
        return AnimatedBuilder(
          animation: _cue,
          builder: (context, _) {
            // Dot pulse only when not paused and the cue is running.
            final pulse = paused ? 0.0 : _pulse.value;
            final dotScale = 1.0 + 0.45 * pulse;
            final foregroundPainter = (paused || _cue.value == 0.0)
                ? null
                : _BorderSweepPainter(
                    progress: _sweep.value,
                    color: mint,
                  );
            return CustomPaint(
              foregroundPainter: foregroundPainter,
              child: Container(
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
                    Transform.scale(
                      scale: dotScale,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          boxShadow: paused
                              ? null
                              : [
                                  BoxShadow(
                                    color: context.gridColors.mint
                                        .withOpacity(0.55 + 0.45 * pulse),
                                    blurRadius: 6 + 6 * pulse,
                                  ),
                                ],
                        ),
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
              ),
            );
          },
        );
      },
    );
  }
}

/// Draws a mint stroke that traces the pill's rounded-rect perimeter
/// clockwise from the top-center, from 0 to [progress] of the way around.
class _BorderSweepPainter extends CustomPainter {
  _BorderSweepPainter({required this.progress, required this.color});

  final double progress; // 0..1
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final radius = size.height / 2; // pill / stadium shape
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    final full = Path()..addRRect(rrect);
    // Rotate the start point to top-center so the sweep reads as starting
    // from where the eye lands and going clockwise.
    final metrics = full.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final total = metric.length;
    final start = total * 0.25; // addRRect starts mid-right; ~25% ≈ top-center

    final swept = total * progress.clamp(0.0, 1.0);
    final path = Path();
    if (start + swept <= total) {
      path.addPath(metric.extractPath(start, start + swept), Offset.zero);
    } else {
      path.addPath(metric.extractPath(start, total), Offset.zero);
      path.addPath(metric.extractPath(0, (start + swept) - total), Offset.zero);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BorderSweepPainter old) =>
      old.progress != progress || old.color != color;
}
