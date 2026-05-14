import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../styles/tokens.dart';

/// Quick helper for Geist Mono text — used for timestamps, coordinates,
/// status pills, "LIVE", build numbers, etc. The design system treats mono
/// as an identity beat, not just a font choice.
class GridMono extends StatelessWidget {
  const GridMono(
    this.text, {
    super.key,
    this.size = 11,
    this.weight = FontWeight.w500,
    this.color,
    this.letterSpacing = 0.04,
    this.uppercase = true,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final Color? color;
  final double letterSpacing;
  final bool uppercase;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      uppercase ? text.toUpperCase() : text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: GoogleFonts.getFont(
        'JetBrains Mono',
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: color ?? GridTokens.text2,
        height: 1.15,
      ),
    );
  }
}
