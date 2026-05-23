import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/in_app_notifier.dart';
import '../styles/tokens.dart';
import '../styles/grid_colors.dart';

class InAppNotificationOverlay extends StatefulWidget {
  const InAppNotificationOverlay({super.key});

  @override
  State<InAppNotificationOverlay> createState() =>
      _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState extends State<InAppNotificationOverlay> {
  final List<InAppNotification> _visible = [];
  final Map<String, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    InAppNotifier.instance.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    InAppNotifier.instance.removeListener(_sync);
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  void _sync() {
    final upstream = InAppNotifier.instance.items;
    final upstreamIds = upstream.map((e) => e.id).toSet();

    final removed = _visible.where((v) => !upstreamIds.contains(v.id)).toList();
    for (final r in removed) {
      _timers.remove(r.id)?.cancel();
    }

    final added = upstream.where(
      (u) => !_visible.any((v) => v.id == u.id),
    );
    for (final a in added) {
      _timers[a.id] = Timer(a.duration, () => _dismiss(a));
    }

    setState(() {
      _visible
        ..clear()
        ..addAll(upstream);
    });
  }

  void _dismiss(InAppNotification n) {
    _timers.remove(n.id)?.cancel();
    InAppNotifier.instance.dismiss(n);
  }

  @override
  Widget build(BuildContext context) {
    if (_visible.isEmpty) return const SizedBox.shrink();
    final topPad = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPad + 8,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final n in _visible)
              _NotificationCard(
                key: ValueKey(n.id),
                notification: n,
                onDismiss: () => _dismiss(n),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatefulWidget {
  final InAppNotification notification;
  final VoidCallback onDismiss;
  const _NotificationCard({
    super.key,
    required this.notification,
    required this.onDismiss,
  });

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctl, curve: Curves.easeOut);
    _ctl.forward();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _animatedDismiss() async {
    if (!mounted) return;
    await _ctl.reverse();
    if (!mounted) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    final accent = _accentFor(context, n.variant);
    final accentSoft = _accentSoftFor(context, n.variant);
    final icon = _iconFor(n.variant);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Dismissible(
            key: ValueKey('dismiss-${n.id}'),
            direction: DismissDirection.horizontal,
            onDismissed: (_) => widget.onDismiss(),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(GridTokens.rLg),
                onTap: n.onTap == null
                    ? null
                    : () {
                        n.onTap!.call();
                        _animatedDismiss();
                      },
                child: Container(
                  decoration: BoxDecoration(
                    color: context.gridColors.surface2,
                    borderRadius: BorderRadius.circular(GridTokens.rLg),
                    border: Border.all(color: context.gridColors.hairline),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accentSoft,
                          borderRadius: BorderRadius.circular(GridTokens.rSm),
                        ),
                        child: Icon(icon, size: 20, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.title,
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: context.gridColors.text,
                                height: 1.25,
                              ),
                            ),
                            if (n.message != null && n.message!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                n.message!,
                                style: GoogleFonts.getFont(
                                  'Geist',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: context.gridColors.text2,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (n.action != null)
                        _ActionButton(
                          label: n.action!.label,
                          color: accent,
                          onTap: () {
                            n.action!.onTap();
                            _animatedDismiss();
                          },
                        )
                      else
                        _CloseButton(onTap: _animatedDismiss),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _accentFor(BuildContext context, InAppNotificationVariant v) {
    final c = context.gridColors;
    switch (v) {
      case InAppNotificationVariant.success:
      case InAppNotificationVariant.info:
        return c.mint;
      case InAppNotificationVariant.warning:
        return c.amber;
      case InAppNotificationVariant.error:
        return c.danger;
    }
  }

  static Color _accentSoftFor(BuildContext context, InAppNotificationVariant v) {
    final c = context.gridColors;
    switch (v) {
      case InAppNotificationVariant.success:
      case InAppNotificationVariant.info:
        return c.mintFaint;
      case InAppNotificationVariant.warning:
        return c.amberSoft;
      case InAppNotificationVariant.error:
        return c.dangerSoft;
    }
  }

  static IconData _iconFor(InAppNotificationVariant v) {
    switch (v) {
      case InAppNotificationVariant.success:
        return Icons.check_rounded;
      case InAppNotificationVariant.info:
        return Icons.info_outline_rounded;
      case InAppNotificationVariant.warning:
        return Icons.warning_amber_rounded;
      case InAppNotificationVariant.error:
        return Icons.error_outline_rounded;
    }
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: GoogleFonts.getFont(
          'Geist',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.close_rounded,
          size: 18,
          color: context.gridColors.text3,
        ),
      ),
    );
  }
}
