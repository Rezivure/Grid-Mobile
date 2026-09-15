import 'package:flutter/material.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';

class CopyAccountDetailsButton extends StatelessWidget {
  final bool copied;
  final void Function()? onPressed;

  const CopyAccountDetailsButton({super.key, required this.copied, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GridButton(
      label: copied ? 'Copied' : 'Copy account details',
      onPressed: onPressed,
      style: GridButtonStyle.primary,
      icon: copied ? Icons.check : Icons.copy,
    );
  }
}
