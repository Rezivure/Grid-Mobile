import 'package:flutter/material.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';

class SignOutButton extends StatelessWidget {
  final void Function()? onPressed;

  const SignOutButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return  GridButton(
      label: 'Sign out',
      icon: Icons.logout,
      style: GridButtonStyle.danger,
      onPressed: onPressed,
    );
  }
}
