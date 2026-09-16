import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';

class NoRecoveryAcknowledgeButton extends StatelessWidget {
  final bool value;
  final void Function(bool value)? onChanged;

  const NoRecoveryAcknowledgeButton({
    super.key,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      borderRadius: BorderRadius.circular(GridTokens.rSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: value,
              activeColor: context.gridColors.mint,
              checkColor: Colors.black,
              onChanged: onChanged != null ? (value) => onChanged!(value ?? false) : null,
            ),
            Expanded(
              child: Text(
                "I understand my password can't be recovered",
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 14,
                  color: context.gridColors.text,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
