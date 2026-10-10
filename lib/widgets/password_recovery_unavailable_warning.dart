
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';

class PasswordRecoveryUnavailableWarning extends StatelessWidget {
  const PasswordRecoveryUnavailableWarning({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.gridColors.dangerSoft,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: context.gridColors.danger,
              ),
              Gap.normal,
              Expanded(
                child: Text(
                  'There is no password reset.',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.gridColors.text,
                  ),
                ),
              ),
            ],
          ),
          Gap.normal,
          Text(
            "Grid never collects your email or phone number, so we have no way "
                "to verify it's you — and no way to reset this password. If you "
                "forget it and you don't have a passkey, your account and "
                "everything in it is gone for good.",
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              color: context.gridColors.text2,
              height: 1.45,
            ),
          ),
          Gap.normal,
          Text(
            'Save it in your password manager before you continue.',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.gridColors.text,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
