import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../styles/tokens.dart';
import '../../styles/grid_colors.dart';

/// Outer chrome for a Grid bottom sheet — top-rounded `bg` container with
/// hairline border on top/left/right and a `SafeArea(top: false)` body.
/// Matches the chrome used by `AddSharingPreferenceModal` (the canonical
/// sharing-windows template) so every sheet feels the same.
class GridSheetContainer extends StatelessWidget {
  const GridSheetContainer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: context.gridColors.bg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(GridTokens.r2Xl),
          ),
          border: Border(
            top: BorderSide(color: context.gridColors.hairline),
            left: BorderSide(color: context.gridColors.hairline),
            right: BorderSide(color: context.gridColors.hairline),
          ),
        ),
        child: SafeArea(top: false, child: child),
      ),
    );
  }
}

/// Compact sheet header — drag handle, title on the left, optional mono
/// subtitle on a second line, close-X on the right. Same dimensions as
/// the canonical sharing-windows modal so every sheet aligns.
class GridSheetHeader extends StatelessWidget {
  const GridSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // handle
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: context.gridColors.hairlineStrong,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.015,
                        color: context.gridColors.text,
                        height: 1.15,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 12.5,
                          color: context.gridColors.text2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: 4),
              ],
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: context.gridColors.text2,
                  size: 22,
                ),
                tooltip: 'Close',
                onPressed:
                    onClose ?? () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
