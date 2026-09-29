import 'package:flutter/material.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';

class OpenDiscordButton extends StatelessWidget {
  final void Function()? onPressed;

  const OpenDiscordButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GridButton(
      label: 'Open Discord',
      onPressed: onPressed,
      style: GridButtonStyle.secondary,
      icon: Icons.open_in_new,
    );
  }
}
