import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/utilities/time_ago_formatter.dart';

import 'user_avatar_bloc.dart';

/// Map pin for a contact. Static — no pulse, no halo. Name pill shows
/// only when selected; the pin tail anchor dot sits at the lat/lng.
class UserMapMarker extends StatelessWidget {
  final String userId;
  final bool isSelected;
  final String? timestamp;

  /// When provided, used directly. Otherwise the marker fires a
  /// one-shot UserRepository lookup on init and caches the result.
  final String? displayName;

  const UserMapMarker({
    Key? key,
    required this.userId,
    this.isSelected = false,
    this.timestamp,
    this.displayName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _UserMapMarkerInner(
      key: ValueKey('marker_$userId'),
      userId: userId,
      isSelected: isSelected,
      timestamp: timestamp,
      displayName: displayName,
    );
  }
}

class _UserMapMarkerInner extends StatefulWidget {
  const _UserMapMarkerInner({
    Key? key,
    required this.userId,
    required this.isSelected,
    required this.timestamp,
    required this.displayName,
  }) : super(key: key);

  final String userId;
  final bool isSelected;
  final String? timestamp;
  final String? displayName;

  @override
  State<_UserMapMarkerInner> createState() => _UserMapMarkerInnerState();
}

class _UserMapMarkerInnerState extends State<_UserMapMarkerInner> {
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _displayName = widget.displayName;
    if (_displayName == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDisplayName());
    }
  }

  Future<void> _loadDisplayName() async {
    if (!mounted) return;
    try {
      final repo = context.read<UserRepository>();
      final user = await repo.getUserById(widget.userId);
      if (!mounted) return;
      final n = user?.displayName?.trim();
      if (n != null && n.isNotEmpty) {
        setState(() => _displayName = n);
      }
    } catch (_) {
      // No repo available — fall back to the localpart below.
    }
  }

  @override
  void didUpdateWidget(_UserMapMarkerInner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.displayName != null &&
        widget.displayName != oldWidget.displayName) {
      setState(() => _displayName = widget.displayName);
    }
  }

  /// Mirrors People list / profile modal: recent (<=10m) is live (mint),
  /// everything else is offline (text3). No amber for contacts.
  Color _statusColor(BuildContext context) {
    final ts = widget.timestamp;
    if (ts == null) return context.gridColors.text3;
    final ago = TimeAgoFormatter.format(ts);
    if (ago == 'Just now' || ago.contains('s ago')) {
      return context.gridColors.mint;
    }
    if (ago.contains('m ago') && !ago.contains('h')) {
      final m = RegExp(r'(\d+)m ago').firstMatch(ago);
      if (m != null) {
        final minutes = int.tryParse(m.group(1)!) ?? 0;
        if (minutes <= 10) return context.gridColors.mint;
      }
    }
    return context.gridColors.text3;
  }

  @override
  Widget build(BuildContext context) {
    final localpart = widget.userId.split(':')[0].replaceFirst('@', '');
    final label = _displayName?.isNotEmpty == true ? _displayName! : localpart;
    final accent = _statusColor(context);

    return SizedBox(
      width: 140,
      height: 110,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          if (widget.isSelected)
            Positioned(
              top: 0,
              child: _NamePill(label: label, accent: accent),
            ),
          Positioned(
            bottom: 0,
            child: _PinBody(
              userId: widget.userId,
              accent: accent,
              selected: widget.isSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _NamePill extends StatelessWidget {
  const _NamePill({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.gridColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.gridColors.hairlineStrong, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.005,
                color: context.gridColors.text,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pin body: avatar in a thin Grid-styled ring, small accent dot below
/// where the avatar bottom meets the lat/lng anchor. Subtle drop shadow
/// gives depth; no glow or halo.
class _PinBody extends StatelessWidget {
  const _PinBody({
    required this.userId,
    required this.accent,
    required this.selected,
  });

  final String userId;
  final Color accent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final innerRing = isDark ? context.gridColors.surface : context.gridColors.bg;
    return SizedBox(
      width: 60,
      height: 64,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: innerRing,
              border: Border.all(
                color: accent,
                width: selected ? 2.5 : 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.30 : 0.18),
                  blurRadius: isDark ? 12 : 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(2),
            child: ClipOval(
              child: UserAvatarBloc(
                key: ValueKey('marker_avatar_$userId'),
                userId: userId,
                size: 50,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                border: Border.all(
                  color: innerRing,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.35 : 0.20),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
