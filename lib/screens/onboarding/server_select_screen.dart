import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:grid_frontend/screens/onboarding/sever_select_views/passkey_view.dart';
import 'package:grid_frontend/screens/onboarding/sever_select_views/password_login_view.dart';
import 'package:grid_frontend/screens/onboarding/sever_select_views/password_signup_view.dart';
import 'package:grid_frontend/screens/onboarding/sever_select_views/username_view.dart';
import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/services/passkey_service.dart';
import 'package:grid_frontend/services/password_auth_service.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/widgets/buttons/use_password_button.dart';
import 'package:grid_frontend/widgets/error_report_dialog.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_circular_progress_indicator.dart';
import 'package:grid_frontend/widgets/info_boxes/inline_message.dart';
import 'package:grid_frontend/widgets/info_boxes/status_message.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';
import 'package:grid_frontend/widgets/password_recovery_unavailable_warning.dart';
import 'package:grid_frontend/widgets/text_fields/user_handle_text_field.dart';
import 'package:grid_frontend/widgets/turnstile_widget.dart';
import 'package:provider/provider.dart';

class UsernameState {
  static const UsernameState empty = UsernameState._("", Colors.transparent);
  static const UsernameState unavailable = UsernameState.error("Username is not available");
  static const UsernameState available =
      UsernameState._("Username is available", Colors.green, icon: Icons.check_circle_outline);

  const UsernameState._(this.message, this.color, {this.icon});
  const UsernameState.error(String message) : this._(message, Colors.red, icon: Icons.error_outline);

  final String message;
  final Color color;
  final IconData? icon;
}

class ServerSelectScreen extends StatefulWidget {
  const ServerSelectScreen({super.key});

  @override
  State<ServerSelectScreen> createState() => _ServerSelectScreenState();

  static Widget buildModernButton({
    required String text,
    required VoidCallback? onPressed,
    required bool isPrimary,
    bool isLoading = false,
    IconData? icon,
  }) {
    if (isLoading) return _LoadingButton(isPrimary: isPrimary);

    return GridButton(
      label: text,
      onPressed: onPressed,
      style: isPrimary ? GridButtonStyle.primary : GridButtonStyle.secondary,
      icon: icon,
    );
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
  static Widget buildTextField({
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
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return DecoratedBox(
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
                        obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: context.gridColors.text3,
                      ),
                      onPressed: onToggleObscure,
                    ),
            ),
          ),
        );
      },
    );
  }
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
  UsernameState _usernameState = UsernameState.empty;
  String get _usernameStatusMessage => _usernameState.message;
  Color get _usernameStatusColor => _usernameState.color;

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

  bool get _isUsernameValid => (_usernameController.text.trim().length >= 5 &&
      _usernameState == UsernameState.available &&
      _turnstileToken != null &&
      !_isPasskeyLoading);

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

    _loginUsernameController.addListener(_resetAuthError);
    _passwordController.addListener(_resetAuthError);
    _confirmPasswordController.addListener(_resetAuthError);
  }

  void _resetAuthError() {
    if (mounted && _authError != null) {
      setState(() => _authError = null);
    }
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
      setState(() => _usernameState == UsernameState.error(error));
      return;
    }

    _checkUsernameAvailability();
  }

  Future<void> _checkUsernameAvailability() async {
    final username = _usernameController.text.trim();

    if (usernameValidationError(username) != null) return;

    bool isAvailable = await Provider.of<AuthProvider>(context, listen: false).checkUsernameAvailability(username);

    setState(() {
      _usernameState = isAvailable ? UsernameState.available : UsernameState.unavailable;
    });
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
      if (_isPasswordLoginStep) {
        return PasswordLoginView(
          loginUsernameController: _loginUsernameController,
          passwordController: _passwordController,
          authError: _authError,
          canLogin: _loginUsernameController.text.trim().isNotEmpty &&
              _passwordController.text.isNotEmpty &&
              _turnstileToken != null &&
              !_isPasswordLoading,
          isPasswordLoading: _isPasswordLoading,
          buildTurnstileWidget: _buildTurnstile,
          onUsePasskey: _showPasskeyLoginStep,
          onLoginWithPassword: _loginWithPassword,
        );
      } else {
        return PasskeyView(
          isPasskeyLoading: _isPasskeyLoading,
          onLoginWithPasskey: _loginWithPasskey,
          onUsePassword: _showPasswordLoginStep,
        );
      }
    }

    if (_usePassword) {
      return PasswordSignupView(
        usernameController: _loginUsernameController,
        passwordController: _passwordController,
        confirmPasswordController: _confirmPasswordController,
        authError: _authError,
        hasNoRecoveryAcknowledged: _acknowledgedNoRecovery,
        onAcknowledgeChanged: (value) {
          if (mounted) setState(() => _acknowledgedNoRecovery = value);
        },
        isPasswordLoading: _isPasswordLoading,
        buildTurnstileWidget: () {
          if (_turnstileToken == null) return _buildTurnstile();
        },
        onShowUsername: _showUsernameStep,
        onSignupWithPassword: _signupWithPassword,
      );
    } else {
      return UsernameView(
        usernameController: _usernameController,
        usernameState: _usernameState,
        isPasskeyLoading: _isPasskeyLoading,
        buildTurnstileWidget: () {
          if (_usernameState == UsernameState.available && _turnstileToken == null) {
            return _buildTurnstile();
          } else {
            return null;
          }
        },
        onSignupWithPasskey: _isUsernameValid ? _signupWithPasskey : null,
        onUsePassword: _isUsernameValid ? _showPasswordSignupStep : null,
      );
    }
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

    if (error is InvalidCredentialsException || error is WeakPasswordException || error is TurnstileFailedException) {
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
      if (!mounted) return;
      await Provider.of<AuthProvider>(context, listen: false).authenticateWithJWT(jwt);
      if (!mounted) return;
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
      if (!mounted) return;
      await Provider.of<AuthProvider>(context, listen: false).authenticateWithJWT(jwt);
      if (!mounted) return;
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
      if (!mounted) return;
      await Provider.of<AuthProvider>(context, listen: false).authenticateWithJWT(jwt);
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
      if (!mounted) return;
      await Provider.of<AuthProvider>(context, listen: false).authenticateWithJWT(jwt);
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

// TODO(Yuki): replace with GridButton once GridButtonStyle is a ThemeExtension
class _LoadingButton extends StatelessWidget {
  final bool isPrimary;

  const _LoadingButton({super.key, required this.isPrimary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: isPrimary ? context.gridColors.mint.withOpacity(0.55) : context.gridColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: isPrimary ? null : Border.all(color: context.gridColors.hairlineStrong),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: 22,
        height: 22,
        child: GridCircularProgressIndicator(
          loading: true,
          isPrimary: isPrimary,
        ),
      ),
    );
  }
}

class StepHeader extends StatelessWidget {
  final Widget? illustration;
  final Widget title;
  final Widget subtitle;

  const StepHeader({super.key, this.illustration, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (illustration != null) ...[
          illustration!,
          Gap.bigger,
          Gap.small,
        ],
        DefaultTextStyle.merge(
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.025,
            color: context.gridColors.text,
            height: 1.1,
          ),
          textAlign: TextAlign.center,
          child: title,
        ),
        Gap.small,
        DefaultTextStyle.merge(
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: context.gridColors.text2,
            height: 1.45,
          ),
          textAlign: TextAlign.center,
          child: subtitle,
        ),
      ],
    );
  }
}
