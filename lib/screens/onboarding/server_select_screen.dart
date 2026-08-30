import 'dart:async';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/services/passkey_service.dart';
import 'package:grid_frontend/services/password_auth_service.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/utilities/error_report.dart';
import 'package:grid_frontend/widgets/error_report_dialog.dart';
import 'package:grid_frontend/widgets/turnstile_widget.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

class ServerSelectScreen extends StatefulWidget {
  @override
  _ServerSelectScreenState createState() => _ServerSelectScreenState();
}

class _ServerSelectScreenState extends State<ServerSelectScreen> with TickerProviderStateMixin {
  // Signup is choose-a-username then either a passkey or a password, and login
  // is either a passkey or a username + password. SMS registration/login was
  // removed, so there are no phone-number or verification-code steps any more.
  bool _isLoginFlow = false;

  /// Signup: the user chose "use a password instead" after picking a handle.
  bool _usePassword = false;

  /// Login: the user chose "use username and password instead" of a passkey.
  bool _isPasswordLoginStep = false;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Controllers
  final TextEditingController _usernameController = TextEditingController();

  // The login step gets its own username controller so the availability-check
  // listener on _usernameController (a signup concern) never runs there. On
  // login "not available" is the *good* answer, so reusing it would show the
  // user a red "Username is not available" for a handle that is rightly theirs.
  final TextEditingController _loginUsernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  // Variables for username availability
  String _usernameStatusMessage = '';
  Color _usernameStatusColor = Colors.transparent;

  Timer? _debounce;

  // Passkey state
  final PasskeyService _passkeyService = PasskeyService();
  bool _isPasskeyLoading = false;
  String? _turnstileToken;

  // Password state
  final PasswordAuthService _passwordAuthService = PasswordAuthService();
  bool _isPasswordLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acknowledgedNoRecovery = false;

  /// Inline error under the password form. Wrong-password and policy failures
  /// belong here, never in showErrorReportDialog - that dialog says "something
  /// is broken, post this in Discord", which is the wrong message for a typo.
  String? _authError;

  /// Bumped on every failed attempt to force a fresh TurnstileWidget.
  ///
  /// TurnstileWidget has no reset API and a Turnstile token is single-use with
  /// a short TTL. With Turnstile required on every password login, one wrong
  /// password spends the token and leaves a widget still showing a green tick
  /// that will never produce another one. Passing `key: ValueKey(_turnstileAttempt)`
  /// makes Flutter tear the WebView down and build a new one, which solves a
  /// fresh challenge. This also fixes the same latent staleness in the passkey
  /// signup path.
  int _turnstileAttempt = 0;

  /// The Turnstile site key is public by design (it is embedded in the widget's
  /// HTML). Read it from dotenv so it is configured in one place, but keep a
  /// literal fallback: a missing .env entry must not brick account creation.
  static const String _fallbackTurnstileSiteKey = '0x4AAAAAACuoM-Fe6MODnKzk';

  String get _turnstileSiteKey {
    final key = dotenv.env['TURNSTILE_SITE_KEY'];
    // Treat an empty value as absent: .env.example ships the key blank, and an
    // empty site key renders a permanently-failing challenge.
    return (key == null || key.isEmpty) ? _fallbackTurnstileSiteKey : key;
  }

  @override
  void initState() {
    super.initState();
    
    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Start animations
    _fadeController.forward();
    _slideController.forward();

    _usernameController.addListener(_onUsernameChanged);
  }

  bool _didReadRouteArgs = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Welcome screen pushes us with `{isLoginFlow: true}` when the user
    // tapped "I already have an account". Without this, _isLoginFlow
    // stayed false and the screen rendered the username (signup) step.
    if (_didReadRouteArgs) return;
    _didReadRouteArgs = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['isLoginFlow'] == true) {
      setState(() => _isLoginFlow = true);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _usernameController.dispose();
    _loginUsernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onUsernameChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _validateUsernameInput();
    });
  }


  void _validateUsernameInput() {
    final error = usernameValidationError(_usernameController.text);

    if (error != null) {
      setState(() {
        _usernameStatusMessage = error;
        _usernameStatusColor = Colors.red;
      });
      return;
    }

    _checkUsernameAvailability();
  }

  Future<void> _checkUsernameAvailability() async {
    final username = _usernameController.text.trim();

    if (usernameValidationError(username) != null) return;

    bool isAvailable = await Provider.of<AuthProvider>(context, listen: false)
        .checkUsernameAvailability(username);

    setState(() {
      if (isAvailable) {
        _usernameStatusMessage = 'Username is available';
        _usernameStatusColor = Colors.green;
      } else {
        _usernameStatusMessage = 'Username is not available';
        _usernameStatusColor = Colors.red;
      }
    });
  }


  Widget _buildModernButton({
    required String text,
    required VoidCallback? onPressed,
    required bool isPrimary,
    bool isLoading = false,
    IconData? icon,
  }) {
    if (isLoading) {
      return Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: isPrimary
              ? context.gridColors.mint.withOpacity(0.55)
              : context.gridColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: isPrimary
              ? null
              : Border.all(color: context.gridColors.hairlineStrong),
        ),
        alignment: Alignment.center,
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            color: isPrimary ? Colors.black : context.gridColors.mint,
            strokeWidth: 2,
          ),
        ),
      );
    }
    return GridButton(
      label: text,
      onPressed: onPressed,
      style: isPrimary ? GridButtonStyle.primary : GridButtonStyle.secondary,
      icon: icon,
    );
  }

  Widget _buildStepHeader({
    required String title,
    required String subtitle,
    Widget? illustration,
  }) {
    return Column(
      children: [
        if (illustration != null) ...[
          illustration,
          const SizedBox(height: 28),
        ],
        Text(
          title,
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.025,
            color: context.gridColors.text,
            height: 1.1,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: context.gridColors.text2,
            height: 1.45,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          // Password is a sub-step of each flow, so back steps out of it
          // rather than abandoning signup/sign-in entirely.
          onPressed: _onBackPressed,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _isLoginFlow ? 'Sign In' : 'Get Started',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 60),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: _buildCurrentStep(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    if (_isLoginFlow) {
      return _isPasswordLoginStep
          ? _buildPasswordLoginStep()
          : _buildPasskeyLoginStep();
    }
    return _usePassword ? _buildPasswordSignupStep() : _buildUsernameStep();
  }

  void _onBackPressed() {
    if (_isPasswordLoginStep) {
      _showPasskeyLoginStep();
      return;
    }
    if (_usePassword) {
      _showUsernameStep();
      return;
    }
    Navigator.pop(context);
  }

  Widget _buildPasskeyLoginStep() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildStepHeader(
          title: 'Welcome Back!',
          subtitle: 'Sign in with your passkey',
          illustration: Container(
            width: 100,
            height: 100,
            alignment: Alignment.center,
            child: Icon(
              Icons.fingerprint,
              size: 48,
              color: colorScheme.primary,
            ),
          ),
        ),

        const SizedBox(height: 40),

        _buildModernButton(
          text: 'Sign in with Passkey',
          onPressed: _isPasskeyLoading ? null : _loginWithPasskey,
          isPrimary: true,
          isLoading: _isPasskeyLoading,
          icon: Icons.fingerprint,
        ),

        const SizedBox(height: 8),

        TextButton(
          onPressed: _isPasskeyLoading ? null : _showPasswordLoginStep,
          child: Text(
            'Use username and password instead',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.gridColors.mint,
            ),
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildUsernameStep() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildStepHeader(
          title: 'Choose Your Handle',
          subtitle: 'This is how others can find and add you on Grid',
          illustration: Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            child: Icon(
              Icons.alternate_email_rounded,
              size: 40,
              color: colorScheme.primary,
            ),
          ),
        ),
        
        const SizedBox(height: 40),
        
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Handle',
              hintText: 'Enter your unique handle',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.all(20),
              prefixIcon: Icon(
                Icons.person_outline,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        
        if (_usernameStatusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: (_usernameStatusColor == Colors.green 
                  ? Colors.green 
                  : Colors.red).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _usernameStatusColor == Colors.green 
                      ? Icons.check_circle_outline 
                      : Icons.error_outline,
                  size: 16,
                  color: _usernameStatusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _usernameStatusMessage,
                    style: TextStyle(
                      color: _usernameStatusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        
        const SizedBox(height: 40),

        // Show Turnstile when username is available
        if (_usernameStatusMessage == 'Username is available' &&
            _turnstileToken == null) ...[
          _buildTurnstile(),
          const SizedBox(height: 16),
        ],

        _buildModernButton(
          text: 'Sign up with Passkey',
          // Stays disabled (grey) until the user has typed at least 5
          // characters, has a confirmed-available username, and has
          // cleared turnstile. The 5-char floor blocks anyone hitting the
          // button on a clearly-too-short handle before the availability
          // check has even fired.
          onPressed: (_usernameController.text.trim().length >= 5 &&
                  _usernameStatusMessage == 'Username is available' &&
                  _turnstileToken != null &&
                  !_isPasskeyLoading)
              ? _signupWithPasskey
              : null,
          isPrimary: true,
          isLoading: _isPasskeyLoading,
          icon: Icons.fingerprint,
        ),

        const SizedBox(height: 8),

        // The second door. Passkeys are the recommended path, but too many
        // people were getting stuck on a device or provider that would not
        // create one and had no way to finish signing up at all (GH #285).
        TextButton(
          onPressed: (_usernameController.text.trim().length >= 5 &&
                  _usernameStatusMessage == 'Username is available' &&
                  !_isPasskeyLoading)
              ? _showPasswordSignupStep
              : null,
          child: Text(
            'Use a password instead',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: (_usernameController.text.trim().length >= 5 &&
                      _usernameStatusMessage == 'Username is available')
                  ? context.gridColors.mint
                  : context.gridColors.text3,
            ),
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }




  /// The Cloudflare Turnstile challenge.
  ///
  /// `key: ValueKey(_turnstileAttempt)` is load-bearing, not cosmetic. See the
  /// comment on [_turnstileAttempt].
  Widget _buildTurnstile() {
    return TurnstileWidget(
      key: ValueKey(_turnstileAttempt),
      siteKey: _turnstileSiteKey,
      onTokenReceived: (token) {
        if (!mounted) return;
        setState(() => _turnstileToken = token);
      },
      onError: () {
        InAppNotifier.instance.show(
          title: 'Verification failed',
          message: 'Please try again.',
          variant: InAppNotificationVariant.error,
        );
      },
    );
  }

  /// Throws away the current Turnstile token and forces a fresh widget.
  /// Call this after *every* failed password attempt: the token has been spent.
  void _resetTurnstile() {
    _turnstileToken = null;
    _turnstileAttempt++;
  }

  /// A text field styled for this screen.
  ///
  /// Deliberately private, and deliberately duplicated.
  /// `login_screen.dart` has a near-identical `_buildModernTextField`, but it
  /// stays there. `test/screens/onboarding/login_screen_test.dart` asserts
  /// `findsOneWidget` on `Icons.lock_outline`, `Icons.visibility_off`,
  /// `Icons.person_outline` and others, so extracting a shared widget - or even
  /// adding one more icon to that screen - flips those assertions to
  /// `findsNWidgets(2)`. A shared `GridPasswordField` is worth having, but it
  /// belongs in its own refactor PR that also rewrites those assertions to
  /// `find.byType(...)`.
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    bool autofocus = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
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
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        autofocus: autofocus,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: textInputAction,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.all(20),
          prefixIcon: Icon(icon, color: colorScheme.primary),
          suffixIcon: onToggleObscure == null
              ? null
              : IconButton(
                  icon: Icon(
                    obscureText
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: context.gridColors.text3,
                  ),
                  onPressed: onToggleObscure,
                ),
        ),
      ),
    );
  }

  Widget _buildInlineMessage(String message, {bool isError = true}) {
    final color = isError ? context.gridColors.danger : context.gridColors.text2;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isError
            ? context.gridColors.dangerSoft
            : context.gridColors.surface2,
        borderRadius: BorderRadius.circular(GridTokens.rSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.getFont(
                'Geist',
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The one thing a user must read before choosing a password on Grid: we
  /// collect no email and no phone number, so there is genuinely nobody who
  /// can let them back in.
  Widget _buildNoRecoveryWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.gridColors.dangerSoft,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: context.gridColors.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'There is no password reset.',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.gridColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Grid never collects your email or phone number, so we have no way "
            "to verify it's you — and no way to reset this password. If you "
            "forget it and you don't have a passkey, your account and "
            "everything in it is gone for good.",
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              color: context.gridColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Save it in your password manager before you continue.',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.gridColors.text,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  /// Support line for the login form.
  ///
  /// "We can't reset your password" comes FIRST, deliberately. Leading with
  /// "ask us on Discord" implies the account is recoverable, which generates
  /// support requests nobody can discharge.
  Widget _buildDiscordHelp() {
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
            recognizer: TapGestureRecognizer()..onTap = _openDiscord,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildPasswordSignupStep() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmation = _confirmPasswordController.text;

    final policyError =
        password.isEmpty ? null : passwordValidationError(password, username: username);
    final matchError = confirmation.isEmpty
        ? null
        : passwordConfirmationError(password, confirmation);

    final isValid = passwordValidationError(password, username: username) == null &&
        passwordConfirmationError(password, confirmation) == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepHeader(
          title: 'Create a Password',
          subtitle: 'Signing up as @$username',
          illustration: Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            child: Icon(
              Icons.password_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),

        const SizedBox(height: 32),

        _buildTextField(
          controller: _passwordController,
          label: 'Password',
          hint: 'At least $kPasswordMinLength characters',
          icon: Icons.lock_outline,
          obscureText: _obscurePassword,
          autofocus: true,
          onToggleObscure: () =>
              setState(() => _obscurePassword = !_obscurePassword),
          onChanged: (_) => setState(() => _authError = null),
        ),

        if (policyError != null) ...[
          const SizedBox(height: 10),
          _buildInlineMessage(policyError),
        ],

        const SizedBox(height: 16),

        _buildTextField(
          controller: _confirmPasswordController,
          label: 'Confirm password',
          hint: 'Re-enter your password',
          icon: Icons.lock_outline,
          obscureText: _obscureConfirmPassword,
          textInputAction: TextInputAction.done,
          onToggleObscure: () => setState(
              () => _obscureConfirmPassword = !_obscureConfirmPassword),
          onChanged: (_) => setState(() => _authError = null),
        ),

        if (matchError != null) ...[
          const SizedBox(height: 10),
          _buildInlineMessage(matchError),
        ],

        const SizedBox(height: 24),

        _buildNoRecoveryWarning(),

        const SizedBox(height: 12),

        // Required, not advisory. The account is unrecoverable and the user
        // has to have seen that before it exists.
        InkWell(
          onTap: () => setState(
              () => _acknowledgedNoRecovery = !_acknowledgedNoRecovery),
          borderRadius: BorderRadius.circular(GridTokens.rSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: _acknowledgedNoRecovery,
                  activeColor: context.gridColors.mint,
                  checkColor: Colors.black,
                  onChanged: (value) =>
                      setState(() => _acknowledgedNoRecovery = value ?? false),
                ),
                Expanded(
                  child: Text(
                    "I understand my password can't be recovered",
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 14,
                      color: context.gridColors.text,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_authError != null) ...[
          const SizedBox(height: 16),
          _buildInlineMessage(_authError!),
        ],

        const SizedBox(height: 24),

        // Normally already solved on the handle step and carried forward. It
        // reappears here only when that token was spent or rejected.
        if (_turnstileToken == null) ...[
          _buildTurnstile(),
          const SizedBox(height: 16),
        ],

        _buildModernButton(
          text: 'Create Account',
          onPressed: (isValid &&
                  _acknowledgedNoRecovery &&
                  _turnstileToken != null &&
                  !_isPasswordLoading)
              ? _signupWithPassword
              : null,
          isPrimary: true,
          isLoading: _isPasswordLoading,
          icon: Icons.person_add_alt_1_rounded,
        ),

        const SizedBox(height: 8),

        TextButton(
          onPressed: _isPasswordLoading ? null : _showUsernameStep,
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

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildPasswordLoginStep() {
    final canSubmit = _loginUsernameController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        _turnstileToken != null &&
        !_isPasswordLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepHeader(
          title: 'Welcome Back!',
          subtitle: 'Sign in with your handle and password',
          illustration: Container(
            width: 100,
            height: 100,
            alignment: Alignment.center,
            child: Icon(
              Icons.lock_outline,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),

        const SizedBox(height: 32),

        _buildTextField(
          controller: _loginUsernameController,
          label: 'Handle',
          hint: 'Your unique handle',
          icon: Icons.person_outline,
          autofocus: true,
          onChanged: (_) => setState(() => _authError = null),
        ),

        const SizedBox(height: 16),

        _buildTextField(
          controller: _passwordController,
          label: 'Password',
          hint: 'Enter your password',
          icon: Icons.lock_outline,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onToggleObscure: () =>
              setState(() => _obscurePassword = !_obscurePassword),
          onChanged: (_) => setState(() => _authError = null),
          onSubmitted: (_) {
            if (canSubmit) _loginWithPassword();
          },
        ),

        if (_authError != null) ...[
          const SizedBox(height: 16),
          _buildInlineMessage(_authError!),
        ],

        const SizedBox(height: 24),

        // Always mounted. Turnstile is required on every password login - it
        // is the only brute-force control, since there is no account lockout.
        _buildTurnstile(),

        const SizedBox(height: 16),

        _buildModernButton(
          text: 'Sign In',
          onPressed: canSubmit ? _loginWithPassword : null,
          isPrimary: true,
          isLoading: _isPasswordLoading,
          icon: Icons.login,
        ),

        const SizedBox(height: 8),

        TextButton(
          onPressed: _isPasswordLoading ? null : _showPasskeyLoginStep,
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

        const SizedBox(height: 20),

        _buildDiscordHelp(),

        const SizedBox(height: 40),
      ],
    );
  }

  // --- Step transitions -----------------------------------------------------
  //
  // Each transition clears the password fields and any inline error, and
  // forces a fresh Turnstile challenge, so a half-filled form never leaks
  // across flows and a token is never reused.

  void _showPasswordSignupStep() {
    setState(() {
      _usePassword = true;
      _authError = null;
      _passwordController.clear();
      _confirmPasswordController.clear();
      _acknowledgedNoRecovery = false;
      _obscurePassword = true;
      _obscureConfirmPassword = true;
      // _turnstileToken is deliberately carried forward: it was solved on the
      // handle step and has not been spent yet.
    });
  }

  void _showUsernameStep() {
    setState(() {
      _usePassword = false;
      _authError = null;
      _passwordController.clear();
      _confirmPasswordController.clear();
      _acknowledgedNoRecovery = false;
    });
  }

  void _showPasswordLoginStep() {
    setState(() {
      _isPasswordLoginStep = true;
      _authError = null;
      _passwordController.clear();
      _obscurePassword = true;
      _resetTurnstile();
    });
  }

  void _showPasskeyLoginStep() {
    setState(() {
      _isPasswordLoginStep = false;
      _authError = null;
      _passwordController.clear();
      _resetTurnstile();
    });
  }

  Future<void> _openDiscord() async {
    final uri = Uri.parse(gridDiscordInvite);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      InAppNotifier.instance.show(
        title: 'Could not open Discord',
        message: gridDiscordInvite,
        variant: InAppNotificationVariant.error,
      );
    }
  }

  /// Turns a password-auth failure into either inline text or the error report
  /// dialog. A wrong password is a user event, not a fault, and must never
  /// open a dialog that tells the user to go and post logs in Discord.
  Future<void> _handlePasswordAuthError(
    Object error, {
    required String action,
    String? username,
  }) async {
    // Whatever went wrong, the Turnstile token is gone: either the server
    // consumed it or it rejected it. Force a fresh challenge before the retry.
    setState(_resetTurnstile);

    if (error is InvalidCredentialsException ||
        error is WeakPasswordException ||
        error is TurnstileFailedException) {
      setState(() => _authError = error.toString());
      return;
    }

    if (!mounted) return;
    await showErrorReportDialog(
      context,
      action: action,
      error: error,
      username: username,
    );
  }

  Future<void> _loginWithPasskey() async {
    setState(() => _isPasskeyLoading = true);
    try {
      final jwt = await _passkeyService.loginWithPasskey();
      await Provider.of<AuthProvider>(context, listen: false)
          .authenticateWithJWT(jwt);
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/main',
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      if (mounted) {
        await showErrorReportDialog(
          context,
          action: 'Passkey login',
          error: e,
        );
      }
    } finally {
      if (mounted) setState(() => _isPasskeyLoading = false);
    }
  }

  Future<void> _signupWithPasskey() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty || _turnstileToken == null) return;

    setState(() => _isPasskeyLoading = true);
    try {
      final jwt = await _passkeyService.signupWithPasskey(
        username: username,
        turnstileToken: _turnstileToken!,
      );
      await Provider.of<AuthProvider>(context, listen: false)
          .authenticateWithJWT(jwt);
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/main',
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      if (mounted) {
        await showErrorReportDialog(
          context,
          action: 'Passkey signup',
          error: e,
          username: username,
        );
      }
    } finally {
      if (mounted) setState(() => _isPasskeyLoading = false);
    }
  }

  Future<void> _signupWithPassword() async {
    final username = _usernameController.text.trim();
    // Never trimmed. See passwordValidationError in utilities/utils.dart:
    // trimming here would create an account whose password nobody can retype,
    // and there is no reset.
    final password = _passwordController.text;
    final token = _turnstileToken;
    if (username.isEmpty || password.isEmpty || token == null) return;

    setState(() {
      _isPasswordLoading = true;
      _authError = null;
    });
    try {
      final jwt = await _passwordAuthService.signup(
        username: username,
        password: password,
        turnstileToken: token,
      );
      await Provider.of<AuthProvider>(context, listen: false)
          .authenticateWithJWT(jwt);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/main',
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      if (mounted) {
        await _handlePasswordAuthError(
          e,
          action: 'Password signup',
          username: username,
        );
      }
    } finally {
      if (mounted) setState(() => _isPasswordLoading = false);
    }
  }

  Future<void> _loginWithPassword() async {
    final username = _loginUsernameController.text.trim();
    final password = _passwordController.text;
    final token = _turnstileToken;
    if (username.isEmpty || password.isEmpty || token == null) return;

    setState(() {
      _isPasswordLoading = true;
      _authError = null;
    });
    try {
      final jwt = await _passwordAuthService.login(
        username: username,
        password: password,
        turnstileToken: token,
      );
      await Provider.of<AuthProvider>(context, listen: false)
          .authenticateWithJWT(jwt);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/main',
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      if (mounted) {
        await _handlePasswordAuthError(
          e,
          action: 'Password login',
          username: username,
        );
      }
    } finally {
      if (mounted) setState(() => _isPasswordLoading = false);
    }
  }
}
