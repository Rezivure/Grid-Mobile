import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../styles/tokens.dart';

enum GridButtonStyle { primary, secondary, ghost, danger }

/// Primary button atom used across the redesigned screens. Wraps Material
/// buttons with the Grid colors, heights, and radii.
class GridButton extends StatelessWidget {
  const GridButton({
    super.key,
    required this.label,
    this.onPressed,
    this.style = GridButtonStyle.primary,
    this.icon,
    this.expand = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final GridButtonStyle style;
  final IconData? icon;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isPrimary = style == GridButtonStyle.primary;
    final isDanger = style == GridButtonStyle.danger;
    final isGhost = style == GridButtonStyle.ghost;

    final Color bg = switch (style) {
      GridButtonStyle.primary => GridTokens.surface2,
      GridButtonStyle.secondary => GridTokens.surface2,
      GridButtonStyle.ghost => Colors.transparent,
      GridButtonStyle.danger => GridTokens.dangerSoft,
    };
    final Color fg = switch (style) {
      GridButtonStyle.primary => GridTokens.mint,
      GridButtonStyle.secondary => GridTokens.text,
      GridButtonStyle.ghost => GridTokens.mint,
      GridButtonStyle.danger => GridTokens.danger,
    };
    final Border? border = switch (style) {
      GridButtonStyle.primary => Border.all(color: GridTokens.mint, width: 1.5),
      GridButtonStyle.secondary => Border.all(color: GridTokens.hairlineStrong),
      _ => null,
    };

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        highlightColor: isPrimary ? GridTokens.mint.withValues(alpha: 0.08) : null,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: border,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.01,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: child) : child;
  }
}

/// Glass / dark floating chrome button — used for nav icons on the map.
class GridNavIconButton extends StatelessWidget {
  const GridNavIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.badgeCount,
    this.badgeColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final int? badgeCount;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: GridTokens.surface.withOpacity(0.92),
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.hairlineStrong, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, color: GridTokens.text, size: 20),
        ),
      ),
    );

    if (badgeCount == null || badgeCount! <= 0) return btn;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        btn,
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: badgeColor ?? GridTokens.amber,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: GridTokens.surface, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              '$badgeCount',
              style: GoogleFonts.getFont(
                'Geist',
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 10,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
