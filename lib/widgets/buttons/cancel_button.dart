import 'package:flutter/material.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';

class CancelButton extends StatelessWidget {
  final void Function()? onPressed;

  const CancelButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GridButton(
      label: 'Cancel',
      style: GridButtonStyle.secondary,
      onPressed: onPressed,
    );
  }
}
