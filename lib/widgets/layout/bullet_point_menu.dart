import 'package:flutter/material.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';

class BulletPointMenu extends StatelessWidget {
  final List<Widget> children;

  const BulletPointMenu({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.gridColors.surface2,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: context.gridColors.hairline),
      ),
      child: Column(
        spacing: Gap.normal.height ?? 0,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
