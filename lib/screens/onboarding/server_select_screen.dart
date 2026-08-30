import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/services/passkey_service.dart';
import 'package:grid_frontend/utilities/error_report.dart';
import 'package:grid_frontend/widgets/error_report_dialog.dart';
import 'package:grid_frontend/widgets/turnstile_widget.dart';
import 'package:grid_frontend/utilities/utils.dart';

class ServerSelectScreen extends StatefulWidget {
  @override
  _ServerSelectScreenState createState() => _ServerSelectScreenState();
}

class _ServerSelectScreenState extends State<ServerSelectScreen> with TickerProviderStateMixin {
  // Signup is a single step (choose a username, create a passkey) and login is
  // a single step (use your passkey). SMS registration/login was removed, so
  // there are no phone-number or verification-code steps any more.
  bool _isLoginFlow = false;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Controllers
  final TextEditingController _usernameController = TextEditingController();

  // Variables for username availability
  String _usernameStatusMessage = '';
  Color _usernameStatusColor = Colors.transparent;

  Timer? _debounce;

  // Passkey state
  final PasskeyService _passkeyService = PasskeyService();
  bool _isPasskeyLoading = false;
  String? _turnstileToken;

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
          onPressed: () => Navigator.pop(context),
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
    // Both flows are a single step now: sign in with an existing passkey, or
    // pick a username and create one.
    return _isLoginFlow ? _buildPasskeyLoginStep() : _buildUsernameStep();
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
          TurnstileWidget(
            siteKey: '0x4AAAAAACuoM-Fe6MODnKzk',
            onTokenReceived: (token) {
              setState(() => _turnstileToken = token);
            },
            onError: () {
              InAppNotifier.instance.show(
                title: 'Verification failed',
                message: 'Please try again.',
                variant: InAppNotificationVariant.error,
              );
            },
          ),
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

        const SizedBox(height: 40),
      ],
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
}
