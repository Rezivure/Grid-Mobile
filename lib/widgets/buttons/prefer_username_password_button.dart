import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/tokens.dart';

import '../../styles/grid_colors.dart';

class PreferUsernamePasswordButton extends StatelessWidget {
  final void Function()? onPressed;

  const PreferUsernamePasswordButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed:onPressed,
      child: Text(
        'Use username and password instead',
        style: GoogleFonts.getFont(
          GridTokens.fontUi,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: context.gridColors.mint,
        ),
      ),
    );
  }
}
