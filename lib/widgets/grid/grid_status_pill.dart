import 'package:flutter/material.dart';

import '../../styles/grid_colors.dart';
import 'grid_mono.dart';

/// Compact status indicator — driving, walking, paused, home, work, custom.
enum GridStatusKind {
  home,
  work,
  driving,
  walking,
  paused,
  live,
  trip,
}

class GridStatusPill extends StatelessWidget {
  const GridStatusPill({
    super.key,
    required this.label,
    this.kind = GridStatusKind.live,
    this.icon,
  });

  final String label;
  final GridStatusKind kind;
  final IconData? icon;

  ({Color bg, Color fg, IconData icon}) _palette(BuildContext context) {
    final c = context.gridColors;
    switch (kind) {
      case GridStatusKind.home:
        return (bg: c.mintSoft, fg: c.mint, icon: Icons.home_rounded);
      case GridStatusKind.driving:
        return (
          bg: c.driving.withOpacity(0.16),
          fg: c.driving,
          icon: Icons.directions_car_rounded
        );
      case GridStatusKind.walking:
        return (
          bg: c.walking.withOpacity(0.16),
          fg: c.walking,
          icon: Icons.directions_walk_rounded
        );
      case GridStatusKind.paused:
        return (
          bg: c.paused.withOpacity(0.16),
          fg: c.paused,
          icon: Icons.pause_circle_outline_rounded
        );
      case GridStatusKind.work:
        return (bg: c.amberSoft, fg: c.amber, icon: Icons.work_outline_rounded);
      case GridStatusKind.trip:
        return (bg: c.amberSoft, fg: c.amber, icon: Icons.luggage_rounded);
      case GridStatusKind.live:
        return (bg: c.mintSoft, fg: c.mint, icon: Icons.circle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? p.icon, size: 11, color: p.fg),
          const SizedBox(width: 5),
          GridMono(label.toUpperCase(), color: p.fg, size: 10, letterSpacing: 0.08),
        ],
      ),
    );
  }
}

/// "LIVE" mono badge — used inline next to a contact's name.
class GridLiveBadge extends StatelessWidget {
  const GridLiveBadge({super.key, this.label = 'LIVE'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.gridColors.mintSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: context.gridColors.mint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          GridMono(label.toUpperCase(), color: context.gridColors.mint, size: 9, letterSpacing: 0.12),
        ],
      ),
    );
  }
}
