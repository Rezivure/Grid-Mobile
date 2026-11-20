import 'package:flutter/material.dart';
import 'package:grid_frontend/screens/onboarding/server_select_screen.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';

import '../../../widgets/buttons/prefer_username_password_button.dart';

class PasskeyView extends StatelessWidget {
  final bool isPasskeyLoading;
  final void Function()? onLoginWithPasskey;
  final void Function()? onUsePassword;

  const PasskeyView({
    super.key,
    required this.isPasskeyLoading,
    required this.onLoginWithPasskey,
    required this.onUsePassword,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        StepHeader(
          illustration: SizedBox(
            width: 100,
            height: 100,
            child: Icon(
              Icons.fingerprint,
              size: 48,
              color: colorScheme.primary,
            ),
          ),
          title: Text("Welcome Back!"),
          subtitle: Text("Sign in with your passkey"),
        ),
        Gap.bigger,
        Gap.bigger,
        ServerSelectScreen.buildModernButton(
          text: 'Sign in with Passkey',
          onPressed: isPasskeyLoading ? null : onLoginWithPasskey,
          isPrimary: true,
          isLoading: isPasskeyLoading,
          icon: Icons.fingerprint,
        ),
        Gap.small,
        PreferUsernamePasswordButton(
          onPressed: isPasskeyLoading ? null : onUsePassword,
        ),
        Gap.bigger,
        Gap.bigger,
      ],
    );
  }
}
