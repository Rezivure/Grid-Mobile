import 'package:flutter/material.dart';

import '../../styles/tokens.dart';
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

  ({Color bg, Color fg, IconData icon}) _palette() {
    switch (kind) {
      case GridStatusKind.home:
        return (bg: GridTokens.mintSoft, fg: GridTokens.mint, icon: Icons.home_rounded);
      case GridStatusKind.driving:
        return (
          bg: GridTokens.driving.withOpacity(0.16),
          fg: GridTokens.driving,
          icon: Icons.directions_car_rounded
        );
      case GridStatusKind.walking:
        return (
          bg: GridTokens.walking.withOpacity(0.16),
          fg: GridTokens.walking,
          icon: Icons.directions_walk_rounded
        );
      case GridStatusKind.paused:
        return (
          bg: GridTokens.paused.withOpacity(0.16),
          fg: GridTokens.paused,
          icon: Icons.pause_circle_outline_rounded
        );
      case GridStatusKind.work:
        return (bg: GridTokens.amberSoft, fg: GridTokens.amber, icon: Icons.work_outline_rounded);
      case GridStatusKind.trip:
        return (bg: GridTokens.amberSoft, fg: GridTokens.amber, icon: Icons.luggage_rounded);
      case GridStatusKind.live:
        return (bg: GridTokens.mintSoft, fg: GridTokens.mint, icon: Icons.circle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette();
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
          GridMono(label, color: p.fg, size: 10, letterSpacing: 0.08),
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
        color: GridTokens.mintSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: GridTokens.mint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          GridMono(label, color: GridTokens.mint, size: 9, letterSpacing: 0.12),
        ],
      ),
    );
  }
}
