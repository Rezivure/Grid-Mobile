import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class UsePasswordButton extends StatelessWidget {
  final void Function()? onPressed;

  const UsePasswordButton({
    super.key,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        'Use a password instead',
        style: GoogleFonts.getFont(
          'Geist',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          // color: @Chandler The 'color' property was previoulsy overridden with the same values that the
          // theming system would already applied automatically
        ),
      ),
    );
  }
}
