import 'package:flutter/material.dart';
import 'package:grid_frontend/styles/grid_colors.dart';

class TermsAndPrivacyButton extends StatelessWidget {
  final void Function()? onPressed;

  const TermsAndPrivacyButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Text(
        'Terms & Privacy',
        style: TextStyle(
          color: context.gridColors.text2,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
