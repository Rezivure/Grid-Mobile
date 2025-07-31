import 'package:flutter/material.dart';

class InitialSplash extends StatelessWidget {
  const InitialSplash({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Container(),
    );
  }
}