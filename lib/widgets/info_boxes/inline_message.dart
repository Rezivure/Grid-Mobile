import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';

class InlineMessage extends StatelessWidget {
  final bool error;
  final bool stretched;
  final Widget child;

  const InlineMessage({super.key, this.error = true, this.stretched = true, required this.child});

  @override
  Widget build(BuildContext context) {
    final color = error ? context.gridColors.danger : context.gridColors.text2;

    return SizedBox(
      width: stretched ? double.infinity : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: error ? context.gridColors.dangerSoft : context.gridColors.surface2,
          borderRadius: BorderRadius.circular(GridTokens.rSm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: color,
              ),
              Gap.small,
              Expanded(
                child: DefaultTextStyle.merge(
                  style: GoogleFonts.getFont(
                    'Geist',
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
