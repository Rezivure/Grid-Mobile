import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/utilities/time_ago_formatter.dart';

import 'user_avatar_bloc.dart';

/// Map pin for a contact. Three parts top-to-bottom: small dark name
/// pill, avatar bubble with status ring + pulse, and a triangle tail
/// pointing at the underlying coordinate. Tap target is the whole
/// 110×110 cell.
class UserMapMarker extends StatefulWidget {
  final String userId;
  final bool isSelected;
  final bool showPulse;
  final String? timestamp;

  /// When provided, used directly. Otherwise the marker fires a
  /// one-shot UserRepository lookup on init and caches the result.
  final String? displayName;

  const UserMapMarker({
    Key? key,
    required this.userId,
    this.isSelected = false,
    this.showPulse = true,
    this.timestamp,
    this.displayName,
  }) : super(key: key);

  @override
  _UserMapMarkerState createState() => _UserMapMarkerState();
}

class _UserMapMarkerState extends State<UserMapMarker>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _selectionController;
  late final AnimationController _bounceController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _bounceAnimation;

  String? _displayName;

  @override
  void initState() {
    super.initState();

    _displayName = widget.displayName;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _selectionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.12,
    ).animate(CurvedAnimation(
      parent: _selectionController,
      curve: Curves.elasticOut,
    ));
    _bounceAnimation = Tween<double>(
      begin: 0.0,
      end: -6.0,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeOutBack,
    ));

    if (widget.showPulse) _pulseController.repeat();
    if (widget.isSelected) _selectionController.forward();

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
  void didUpdateWidget(UserMapMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _selectionController.forward();
        _bounceController.forward(from: 0);
      } else {
        _selectionController.reverse();
        _bounceController.reverse();
      }
    }
    if (widget.showPulse != oldWidget.showPulse) {
      if (widget.showPulse) {
        _pulseController.repeat();
      } else {
        _pulseController.stop();
      }
    }
    if (widget.displayName != null &&
        widget.displayName != oldWidget.displayName) {
      setState(() => _displayName = widget.displayName);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _selectionController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  /// Live > 10 min ago → amber. Live > 1 hr → text3. Recent → mint.
  Color get _statusColor {
    final ts = widget.timestamp;
    if (ts == null) return GridTokens.mint;
    final ago = TimeAgoFormatter.format(ts);
    if (ago == 'Just now' || ago.contains('s ago')) return GridTokens.mint;
    if (ago.contains('m ago')) {
      final m = int.tryParse(ago.split(' ').first) ?? 0;
      return m <= 10 ? GridTokens.mint : GridTokens.amber;
    }
    if (ago.contains('h ago')) return GridTokens.amber;
    return GridTokens.text3;
  }

  @override
  Widget build(BuildContext context) {
    final localpart = widget.userId.split(':')[0].replaceFirst('@', '');
    final label = _displayName?.isNotEmpty == true ? _displayName! : localpart;
    final accent = _statusColor;

    return AnimatedBuilder(
      animation: Listenable.merge(
        [_pulseAnimation, _scaleAnimation, _bounceAnimation],
      ),
      builder: (context, _) {
        return Transform.translate(
          // Bounce on selection only — the parent Positioned already
          // anchors the bottom of the cell (the pin tail tip) to the
          // contact's lat/lng.
          offset: Offset(0, _bounceAnimation.value),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: SizedBox(
              width: 140,
              height: 110,
              child: Stack(
                alignment: Alignment.bottomCenter,
                clipBehavior: Clip.none,
                children: [
                  // Pulse rings behind the avatar — bottom of the
                  // stack so the avatar paints over the fading
                  // halos.
                  if (widget.showPulse)
                    Positioned(
                      bottom: 16,
                      child: _PulseHalos(
                        animation: _pulseAnimation,
                        color: accent,
                      ),
                    ),

                  // Name pill above the avatar.
                  Positioned(
                    top: 0,
                    child: _NamePill(label: label, accent: accent),
                  ),

                  // Avatar bubble + tail.
                  Positioned(
                    bottom: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AvatarBubble(
                          userId: widget.userId,
                          accent: accent,
                          selected: widget.isSelected,
                        ),
                        CustomPaint(
                          size: const Size(14, 9),
                          painter: _TailPainter(color: accent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
        color: GridTokens.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GridTokens.hairlineStrong, width: 1),
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
              boxShadow: [
                BoxShadow(color: accent.withOpacity(0.6), blurRadius: 4),
              ],
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
                color: GridTokens.text,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseHalos extends StatelessWidget {
  const _PulseHalos({required this.animation, required this.color});
  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = animation.value;
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 48 + (32 * t),
            height: 48 + (32 * t),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.18 * (1 - t)),
            ),
          ),
          Container(
            width: 48 + (16 * t),
            height: 48 + (16 * t),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.26 * (1 - t)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({
    required this.userId,
    required this.accent,
    required this.selected,
  });

  final String userId;
  final Color accent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Tight surface ring around the avatar so the image sits
        // inside a clean halo, no white 3D mock-up.
        color: GridTokens.surface,
        border: Border.all(
          color: accent,
          width: selected ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          if (selected)
            BoxShadow(
              color: accent.withOpacity(0.45),
              blurRadius: 14,
              spreadRadius: 1,
            ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: ClipOval(
        child: UserAvatarBloc(
          key: ValueKey('marker_avatar_$userId'),
          userId: userId,
          size: 46,
        ),
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final fillPaint = Paint()..color = color;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.save();
    canvas.translate(0, 1);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _TailPainter old) => old.color != color;
}
