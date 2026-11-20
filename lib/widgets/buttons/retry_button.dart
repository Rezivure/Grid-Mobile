import 'package:flutter/material.dart';

class RetryButton extends StatelessWidget {
  final void Function()? onPressed;

  const RetryButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    ColorScheme scheme = ColorScheme.of(context);

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: const Text(
        'Retry',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    );
  }
}
