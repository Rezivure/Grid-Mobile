import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/screens/onboarding/server_select_screen.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/buttons/no_recovery_acknowledge_button.dart';
import 'package:grid_frontend/widgets/info_boxes/inline_message.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';

import '../../../utilities/utils.dart';
import '../../../widgets/password_recovery_unavailable_warning.dart';

class PasswordSignupView extends StatefulWidget {
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;

  final String? authError;

  final bool hasNoRecoveryAcknowledged;
  final bool isPasswordLoading;
  final bool turnstileGranted;

  final Widget? Function() buildTurnstileWidget;

  final void Function(bool value)? onAcknowledgeChanged;
  final void Function()? onSignupWithPassword;
  final void Function()? onShowUsername;

  const PasswordSignupView({
    super.key,
    required this.usernameController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.authError,
    required this.hasNoRecoveryAcknowledged,
    required this.isPasswordLoading,
    required this.turnstileGranted,
    required this.buildTurnstileWidget,
    required this.onSignupWithPassword,
    required this.onAcknowledgeChanged,
    required this.onShowUsername,
  });

  @override
  State<PasswordSignupView> createState() => _PasswordSignupViewState();
}

class _PasswordSignupViewState extends State<PasswordSignupView> {
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String? _policyError;
  String? _matchError;
  bool get _isPasswordValid => _policyError == null && _matchError == null;

  @override
  void initState() {
    super.initState();

    _setupControllerListener();
  }

  @override
  void didUpdateWidget(covariant PasswordSignupView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.usernameController != widget.usernameController ||
        oldWidget.passwordController != widget.passwordController ||
        oldWidget.confirmPasswordController != widget.confirmPasswordController) {
      _removeListener(oldWidget.usernameController, oldWidget.passwordController, oldWidget.confirmPasswordController);
      _setupControllerListener();
    }
  }

  void _removeListener(
    TextEditingController? usernameController,
    TextEditingController? passwordController,
    TextEditingController? confirmPasswordController,
  ) {
    usernameController?.removeListener(_onInputChanged);
    passwordController?.removeListener(_onInputChanged);
    confirmPasswordController?.removeListener(_onInputChanged);
  }

  void _setupControllerListener() {
    widget.usernameController.addListener(_onInputChanged);
    widget.passwordController.addListener(_onInputChanged);
    widget.confirmPasswordController.addListener(_onInputChanged);
    _verifyInput();
  }

  void _onInputChanged() => _verifyInput(rebuild: true);

  void _verifyInput({bool rebuild = false}) {
    final username = widget.usernameController.text.trim();
    final password = widget.passwordController.text;
    final confirmation = widget.confirmPasswordController.text;

    final policyError = passwordValidationError(password, username: username);
    final matchError = passwordConfirmationError(password, confirmation);

    void update() {
      _policyError = policyError;
      _matchError = matchError;
    }

    if (mounted && (policyError != _policyError || matchError != _matchError)) {
      if (rebuild) {
        setState(update);
      } else {
        update();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget? turnstile = widget.buildTurnstileWidget();
    if (turnstile != null) {
      turnstile = Padding(
        padding: EdgeInsets.only(bottom: Gap.big.height ?? 0),
        child: turnstile,
      );
    }

    bool canCreateAccount =
        (_isPasswordValid && widget.hasNoRecoveryAcknowledged && widget.turnstileGranted && !widget.isPasswordLoading);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHeader(
          illustration: SizedBox(
            width: 96,
            height: 96,
            child: Icon(
              Icons.password_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text('Create a Password'),
          subtitle: ValueListenableBuilder(
            valueListenable: widget.usernameController,
            builder: (context, value, child) {
              return Text('Signing up as @${value.text.trim()}');
            },
          ),
        ),

        const SizedBox(height: 32),

        ServerSelectScreen.buildTextField(
          controller: widget.passwordController,
          label: 'Password',
          hint: 'At least $kPasswordMinLength characters',
          icon: Icons.lock_outline,
          obscureText: _obscurePassword,
          autofocus: true,
          onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
        ),

        Visibility(
          visible: _policyError != null,
          child: Padding(
            padding: EdgeInsets.only(top: Gap.small.height ?? 0),
            child: InlineMessage(
              child: Text(_policyError ?? ""),
            ),
          ),
        ),

        Gap.big,

        ServerSelectScreen.buildTextField(
          controller: widget.confirmPasswordController,
          label: 'Confirm password',
          hint: 'Re-enter your password',
          icon: Icons.lock_outline,
          obscureText: _obscureConfirmPassword,
          textInputAction: TextInputAction.done,
          onToggleObscure: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
        ),

        Visibility(
          visible: _matchError != null,
          child: Padding(
            padding: EdgeInsets.only(top: Gap.small.height ?? 0),
            child: InlineMessage(
              child: Text(_matchError ?? ""),
            ),
          ),
        ),

        Gap.biggest,

        SizedBox(
          width: double.infinity,
          child: const PasswordRecoveryUnavailableWarning(),
        ),

        Gap.big,

        // Required, not advisory. The account is unrecoverable and the user
        // has to have seen that before it exists.
        NoRecoveryAcknowledgeButton(
          value: widget.hasNoRecoveryAcknowledged,
          onChanged: widget.onAcknowledgeChanged,
        ),

        Visibility(
          visible: widget.authError != null,
          child: Padding(
            padding: EdgeInsets.only(top: Gap.big.height ?? 0),
            child: InlineMessage(
              child: Text(widget.authError ?? ""),
            ),
          ),
        ),

        Gap.biggest,

        // Normally already solved on the handle step and carried forward. It
        // reappears here only when that token was spent or rejected.
        if (turnstile != null) turnstile,

        ServerSelectScreen.buildModernButton(
          text: 'Create Account',
          onPressed: canCreateAccount ? widget.onSignupWithPassword : null,
          isPrimary: canCreateAccount,
          isLoading: widget.isPasswordLoading,
          icon: Icons.person_add_alt_1_rounded,
        ),

        Gap.small,

        TextButton(
          onPressed: widget.isPasswordLoading ? null : widget.onShowUsername,
          child: Text(
            'Use a passkey instead',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.gridColors.mint,
            ),
          ),
        ),

        Gap.bigger,
        Gap.bigger,
      ],
    );
  }

  @override
  void dispose() {
    _removeListener(widget.usernameController, widget.passwordController, widget.confirmPasswordController);
    super.dispose();
  }
}
