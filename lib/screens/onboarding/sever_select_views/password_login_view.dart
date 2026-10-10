import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/screens/onboarding/server_select_screen.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/buttons/use_passkey_button.dart';
import 'package:grid_frontend/widgets/info_boxes/inline_message.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/in_app_notifier.dart';
import '../../../utilities/error_report.dart';

class PasswordLoginView extends StatefulWidget {
  final TextEditingController loginUsernameController;
  final TextEditingController passwordController;
  final String? authError;
  final bool canLogin;
  final bool isPasswordLoading;
  final Widget Function() buildTurnstileWidget;
  final void Function()? onUsePasskey;
  final void Function()? onLoginWithPassword;

  const PasswordLoginView({
    super.key,
    required this.loginUsernameController,
    required this.passwordController,
    required this.authError,
    required this.isPasswordLoading,
    required this.canLogin,
    required this.buildTurnstileWidget,
    required this.onUsePasskey,
    required this.onLoginWithPassword,
  });

  @override
  State<PasswordLoginView> createState() => _PasswordLoginViewState();
}

class _PasswordLoginViewState extends State<PasswordLoginView> {
  bool obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHeader(
          illustration: SizedBox(
            width: 100,
            height: 100,
            child: Icon(
              Icons.lock_outline,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text('Welcome Back!'),
          subtitle: Text('Sign in with your handle and password'),
        ),

        const SizedBox(height: 32),

        ServerSelectScreen.buildTextField(
          controller: widget.loginUsernameController,
          label: 'Handle',
          hint: 'Your unique handle',
          icon: Icons.person_outline,
          autofocus: true,
        ),

        Gap.bigger,

        ServerSelectScreen.buildTextField(
            controller: widget.passwordController,
            label: 'Password',
            hint: 'Enter your password',
            icon: Icons.lock_outline,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            onToggleObscure: () => setState(() => obscurePassword = !obscurePassword),
            onSubmitted: (_) {
              if (widget.canLogin) widget.onLoginWithPassword?.call();
            }),

        Visibility(
          visible: widget.authError != null,
          child: Padding(
            padding: EdgeInsets.only(top: Gap.big.height ?? 0),
            child: InlineMessage(
              child: Text(widget.authError ?? ""),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Always mounted. Turnstile is required on every password login - it
        // is the only brute-force control, since there is no account lockout.
        widget.buildTurnstileWidget(),

        Gap.big,

        ServerSelectScreen.buildModernButton(
          text: 'Sign In',
          onPressed: widget.canLogin ? widget.onLoginWithPassword : null,
          isPrimary: true,
          isLoading: widget.isPasswordLoading,
          icon: Icons.login,
        ),

        Gap.small,

        UsePasskeyButton(
          onPressed: widget.isPasswordLoading ? null : widget.onUsePasskey,
        ),

        Gap.bigger,

        DiscordHelp(onOpenDiscord: () => _openDiscord(context)),

        Gap.bigger, Gap.bigger,
      ],
    );
  }

  Future<void> _openDiscord(BuildContext context) async {
    final uri = Uri.parse(gridDiscordInvite);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      InAppNotifier.instance.show(
        title: 'Could not open Discord',
        message: gridDiscordInvite,
        variant: InAppNotificationVariant.error,
      );
    }
  }
}

/// Support line for the login form.
///
/// "We can't reset your password" comes FIRST, deliberately. Leading with
/// "ask us on Discord" implies the account is recoverable, which generates
/// support requests nobody can discharge.

class DiscordHelp extends StatelessWidget {
  final void Function()? onOpenDiscord;

  const DiscordHelp({super.key, this.onOpenDiscord});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: GoogleFonts.getFont(
          'Geist',
          fontSize: 13,
          color: context.gridColors.text3,
          height: 1.45,
        ),
        children: [
          const TextSpan(text: "Can't sign in? "),
          TextSpan(
            text: "We can't reset your password",
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.gridColors.text2,
              height: 1.45,
            ),
          ),
          const TextSpan(text: ' — but if something else is wrong, '),
          TextSpan(
            text: 'ask us on Discord',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.gridColors.mint,
              height: 1.45,
            ),
            recognizer: TapGestureRecognizer()..onTap = onOpenDiscord,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
