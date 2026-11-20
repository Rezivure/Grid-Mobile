import 'package:flutter/material.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';

class AddPasskeyNowButton extends StatelessWidget {
  final void Function()? onPressed;

  const AddPasskeyNowButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.gridColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.gridColors.mint,
          width: 2,
        ),
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fingerprint, color: context.gridColors.mint, size: 20),
            Gap.small,
            Text(
              'Add Passkey Now',
              style: TextStyle(
                color: context.gridColors.mint,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
