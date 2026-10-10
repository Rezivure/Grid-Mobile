import 'package:flutter/material.dart';

class RemindMeLaterButton extends StatelessWidget {
  final void Function()? onPressed;

  const RemindMeLaterButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Text(
        'Remind Me Later',
        style: TextStyle(
          color: ColorScheme.of(context).onSurface.withValues(alpha: 0.6),
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
    );
  }
}
