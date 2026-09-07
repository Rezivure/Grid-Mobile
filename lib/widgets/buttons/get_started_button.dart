import 'package:flutter/material.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';

class GetStartedButton extends StatelessWidget {
  final void Function()? onPressed;

  const GetStartedButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GridButton(
      label: 'Get started',
      onPressed: onPressed,
    );
  }
}
