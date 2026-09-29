import 'package:flutter/material.dart';
import 'package:grid_frontend/styles/grid_colors.dart';

class GridCloseButton extends StatelessWidget {
  final void Function()? onPressed;

  const GridCloseButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: context.gridColors.text2,
      ),
      child: const Text('Close'),
    );
  }
}
