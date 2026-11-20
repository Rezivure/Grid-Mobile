import 'package:flutter/material.dart';
import 'package:grid_frontend/screens/onboarding/server_select_screen.dart';
import 'package:grid_frontend/widgets/buttons/use_password_button.dart';
import 'package:grid_frontend/widgets/info_boxes/status_message.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';
import 'package:grid_frontend/widgets/text_fields/user_handle_text_field.dart';

class UsernameView extends StatelessWidget {
  final TextEditingController usernameController;
  final UsernameState usernameState;
  final bool isPasskeyLoading;
  final Widget? Function() buildTurnstileWidget;
  final void Function()? onSignupWithPasskey;
  final void Function()? onUsePassword;

  const UsernameView({
    super.key,
    required this.usernameController,
    required this.usernameState,
    required this.isPasskeyLoading,
    required this.buildTurnstileWidget,
    required this.onSignupWithPasskey,
    required this.onUsePassword,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget? turnstile = buildTurnstileWidget();
    if (turnstile != null) {
      turnstile = Padding(
        padding: EdgeInsets.only(bottom: Gap.bigger.height ?? 0),
        child: turnstile,
      );
    }

    return Column(
      children: [
        StepHeader(
          illustration: SizedBox(
            width: 96,
            height: 96,
            child: Icon(
              Icons.alternate_email_rounded,
              size: 40,
              color: colorScheme.primary,
            ),
          ),
          title: Text('Choose Your Handle'),
          subtitle: Text('This is how others can find and add you on Grid'),
        ),

        Gap.bigger,
        Gap.bigger,

        // TODO(Yuki): Check whether this decoration can be removed, it seems to be a no-op
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: UserHandleTextField(
            controller: usernameController,
          ),
        ),
        Visibility(
          visible: usernameState.message.isNotEmpty,
          child: Padding(
            padding: EdgeInsets.only(top: Gap.normal.height ?? 0),
            child: StatusMessage(
              text: Text(usernameState.message),
              color: usernameState.color,
              icon: usernameState.icon,
            ),
          ),
        ),
        Gap.bigger,
        Gap.bigger,


        if (turnstile != null) turnstile,

        ServerSelectScreen.buildModernButton(
          text: 'Sign up with Passkey',
          // Stays disabled (grey) until the user has typed at least 5
          // characters, has a confirmed-available username, and has
          // cleared turnstile. The 5-char floor blocks anyone hitting the
          // button on a clearly-too-short handle before the availability
          // check has even fired.
          onPressed: onSignupWithPasskey,
          isPrimary: true,
          isLoading: isPasskeyLoading,
          icon: Icons.fingerprint,
        ),

        Gap.small,

        // The second door. Passkeys are the recommended path, but too many
        // people were getting stuck on a device or provider that would not
        // create one and had no way to finish signing up at all (GH #285).
        UsePasswordButton(
          onPressed: onUsePassword,
        ),

        Gap.bigger,
        Gap.bigger,
      ],
    );
  }
}
