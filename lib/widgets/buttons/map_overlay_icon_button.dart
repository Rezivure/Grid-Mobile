import 'package:flutter/material.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';

/// Floating map-overlay icon button styled to match the bottom sheet's
/// `GridNavIconButton`. Used for the globe/center buttons in the right
/// FAB column — the compass keeps its own builder because it carries the
/// rotating compass rose inside the same chrome.
class MapOverlayIconButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  final String? tooltip;

  const MapOverlayIconButton({
    super.key,
    required this.icon,
    required this.active,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FloatingActionButton.small(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      tooltip: tooltip,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        side: active
            ? BorderSide(color: context.gridColors.mint, width: 1.5)
            : (isDark ? BorderSide(color: context.gridColors.hairline, width: 1) : null) ?? BorderSide(),
      ),
      backgroundColor: active ? context.gridColors.mintFaint : context.gridColors.surface.withValues(alpha: 0.92),
      foregroundColor: active ? context.gridColors.mint : context.gridColors.text,
      onPressed: onPressed,
      child: Icon(
        icon,
        size: 20,
      ),
    );
  }
}
