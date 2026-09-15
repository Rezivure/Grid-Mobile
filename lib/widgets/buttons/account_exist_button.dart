import 'package:flutter/material.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';

class AccountExistButton extends StatelessWidget {
  final void Function()? onPressed;

  const AccountExistButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GridButton(
      // TODO(Yuki): localize
      label: 'I already have an account',
      style: GridButtonStyle.ghost,
      onPressed: onPressed,
    );
  }
}
