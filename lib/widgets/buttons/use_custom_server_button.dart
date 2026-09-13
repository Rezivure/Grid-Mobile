
import 'package:flutter/material.dart';
import 'package:grid_frontend/styles/grid_colors.dart';

class UseCustomServerButton extends StatelessWidget {

  final void Function()? onPressed;

  const UseCustomServerButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: context.gridColors.mint,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_rounded, size: 14, color: context.gridColors.mint),
          SizedBox(width: 4),
          Text(
            'Use a custom server',
            style: TextStyle(
              fontSize: 12.5,
              color: context.gridColors.mint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
