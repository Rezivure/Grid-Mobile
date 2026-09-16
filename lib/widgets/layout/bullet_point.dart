import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';

class BulletPoint extends StatelessWidget {
  final Widget icon;
  final Widget child;

  const BulletPoint({super.key, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconTheme.merge(
          data: IconThemeData(size: 18, color: context.gridColors.text2),
          child: icon,
        ),
        Gap.normal,
        Expanded(
          child: DefaultTextStyle.merge(
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: context.gridColors.text2,
              height: 1.35,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}
