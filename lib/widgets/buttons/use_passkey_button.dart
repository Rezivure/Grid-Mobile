import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/grid_colors.dart';

class UsePasskeyButton extends StatelessWidget {
  final void Function()? onPressed;

  const UsePasskeyButton({
    super.key,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        'Use a passkey instead',
        style: GoogleFonts.getFont(
          'Geist',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: context.gridColors.mint,
        ),
      ),
    );
  }
}
