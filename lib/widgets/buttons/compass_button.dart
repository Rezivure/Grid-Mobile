import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';

import '../../screens/map/compass_geometry.dart';

class CompassButton extends StatelessWidget {
  final void Function()? onPressed;
  final double rotation;

  const CompassButton({
    super.key,
    this.onPressed,
    required this.rotation,
  });

  @override
  Widget build(BuildContext context) {
    bool darkMode = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        onTap: onPressed,
        child: Ink(
          // TODO(Yuki): remove sizes
          width: 40,
          height: 40,
          // TODO(Yuki): seems like the default shadow container for everything, move into separate widget
          decoration: BoxDecoration(
            color: context.gridColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: darkMode ? Border.all(color: context.gridColors.hairline, width: 1) : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: darkMode ? 0.28 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // TODO(Yuki): animate this (maybe pass animation directly into painter)
              Transform.rotate(
                angle: compassRoseAngleRadians(rotation),
                child: CustomPaint(
                  size: const Size(26, 26),
                  painter: CompassPainter(
                    northColor: context.gridColors.danger,
                    southColor: context.gridColors.text2,
                  ),
                ),
              ),
              Positioned(
                top: 4,
                child: Text(
                  'N',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: context.gridColors.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompassPainter extends CustomPainter {
  final Color northColor;
  final Color southColor;

  CompassPainter({
    required this.northColor,
    required this.southColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint northPaint = Paint()
      ..color = northColor
      ..style = PaintingStyle.fill;

    final Paint southPaint = Paint()
      ..color = southColor
      ..style = PaintingStyle.fill;

    final double centerX = size.width / 2;
    final double centerY = size.height / 2;

    // North arrow (red) - using ui.Path to avoid conflict with latlong2.Path
    final ui.Path northPath = ui.Path();
    northPath.moveTo(centerX, centerY - 10); // Top point
    northPath.lineTo(centerX - 3, centerY); // Left point
    northPath.lineTo(centerX + 3, centerY); // Right point
    northPath.close();

    // South arrow (gray)
    final ui.Path southPath = ui.Path();
    southPath.moveTo(centerX, centerY + 10); // Bottom point
    southPath.lineTo(centerX - 3, centerY); // Left point
    southPath.lineTo(centerX + 3, centerY); // Right point
    southPath.close();

    canvas.drawPath(northPath, northPaint);
    canvas.drawPath(southPath, southPaint);
  }

  @override
  bool shouldRepaint(CompassPainter oldDelegate) {
    return oldDelegate.northColor != northColor || oldDelegate.southColor != southColor;
  }
}
