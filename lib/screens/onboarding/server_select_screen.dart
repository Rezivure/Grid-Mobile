import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:flutter_intl_phone_field/flutter_intl_phone_field.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/providers/auth_provider.dart';

class ServerSelectScreen extends StatefulWidget {
  @override
  _ServerSelectScreenState createState() => _ServerSelectScreenState();
}

class _ServerSelectScreenState extends State<ServerSelectScreen> with TickerProviderStateMixin {
  int _currentStep = 0; // 0: Enter Username, 1: Enter Phone Number, 2: Verify SMS Code
  bool _isLoginFlow = false;
  bool _isLoading = false;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  // Variables for username availability
  String _usernameStatusMessage = '';
  Color _usernameStatusColor = Colors.transparent;

  Timer? _debounce;
  String _fullPhoneNumber = '';
  bool _hasAttemptedAutoSubmit = false;

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
    _codeController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _usernameController.dispose();
    _codeController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onUsernameChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _validateUsernameInput();
    });
  }

  void _onCodeChanged() {
    setState(() {}); // Trigger rebuild when code changes
    
    // Auto-submit when 6 digits are entered (only if not already attempted)
    if (_codeController.text.trim().length == 6 && !_hasAttemptedAutoSubmit && !_isLoading) {
      _hasAttemptedAutoSubmit = true;
      _submitVerificationCode();
    }
  }

  void _validateUsernameInput() {
    String username = _usernameController.text;

    if (username.length < 5) {
      setState(() {
        _usernameStatusMessage = 'Username must be at least 5 characters and no special characters or spaces.';
        _usernameStatusColor = Colors.red;
      });
      return;
    }

    _checkUsernameAvailability();
  }

  Future<void> _checkUsernameAvailability() async {
    String username = _usernameController.text;

    if (username.isNotEmpty && username.length >= 5) {
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
  }

  void _animateToNextStep() {
    _slideController.reset();
    _fadeController.reset();
    Future.delayed(const Duration(milliseconds: 100), () {
      _fadeController.forward();
      _slideController.forward();
    });
  }

  Widget _buildProgressIndicator() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: List.generate(3, (index) {
          final isActive = index <= _currentStep;
          final isCompleted = index < _currentStep;
          
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  if (index > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: isCompleted 
                              ? colorScheme.primary 
                              : colorScheme.outline.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isActive ? colorScheme.primary : colorScheme.outline.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: isCompleted
                        ? Icon(
                            Icons.check,
                            size: 16,
                            color: colorScheme.onPrimary,
                          )
                        : Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: isActive ? colorScheme.onPrimary : colorScheme.onSurface.withOpacity(0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ),
                  if (index < 2)
                    Expanded(
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: isCompleted 
                              ? colorScheme.primary 
                              : colorScheme.outline.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildModernButton({
    required String text,
    required VoidCallback? onPressed,
    required bool isPrimary,
    bool isLoading = false,
    IconData? icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onPressed != null && !isLoading;
    
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isPrimary && isEnabled ? [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ] : null,
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary 
              ? (isEnabled ? colorScheme.primary : colorScheme.primary.withOpacity(0.5))
              : Colors.transparent,
          foregroundColor: isPrimary 
              ? (isEnabled ? colorScheme.onPrimary : colorScheme.onPrimary.withOpacity(0.5))
              : (isEnabled ? colorScheme.primary : colorScheme.primary.withOpacity(0.5)),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isPrimary ? BorderSide.none : BorderSide(
              color: isEnabled 
                  ? colorScheme.outline.withOpacity(0.2)
                  : colorScheme.outline.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: isPrimary ? colorScheme.onPrimary : colorScheme.primary,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isPrimary 
                          ? (isEnabled ? colorScheme.onPrimary : colorScheme.onPrimary.withOpacity(0.5))
                          : (isEnabled ? colorScheme.primary : colorScheme.primary.withOpacity(0.5)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStepHeader({
    required String title,
    required String subtitle,
    Widget? illustration,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Column(
      children: [
        if (illustration != null) ...[
          illustration,
          const SizedBox(height: 24),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'STEP ${_currentStep + 1} OF 3',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.7),
            height: 1.4,
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
      backgroundColor: colorScheme.background,
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
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildProgressIndicator(),
            const SizedBox(height: 40),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: _buildCurrentStep(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildUsernameStep();
      case 1:
        return _buildPhoneNumberStep();
      case 2:
        return _buildVerifySmsStep();
      default:
        return Container();
    }
  }

  Widget _buildUsernameStep() {
    final colorScheme = Theme.of(context).colorScheme;
    String username = _usernameController.text.isNotEmpty ? _usernameController.text : 'default';

    return Column(
      children: [
        _buildStepHeader(
          title: 'Choose Your Username',
          subtitle: 'This is how others can find and add you on Grid',
          illustration: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colorScheme.primary.withOpacity(0.1),
                      colorScheme.primary.withOpacity(0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.3, 0.7, 1.0],
                  ),
                ),
                child: RandomAvatar(
                  username.toLowerCase(),
                  height: 80,
                  width: 80,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your unique avatar!',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
              labelText: 'Username',
              hintText: 'Enter your unique username',
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
        
        _buildModernButton(
          text: 'Continue',
          onPressed: (_usernameStatusMessage == 'Username is available') && !_isLoading
              ? () {
                  setState(() {
                    _currentStep = 1;
                  });
                  _animateToNextStep();
                }
              : null,
          isPrimary: true,
          isLoading: _isLoading,
          icon: Icons.arrow_forward,
        ),
        
        const SizedBox(height: 16),
        
        _buildModernButton(
          text: 'Already have an account? Sign In',
          onPressed: () {
            setState(() {
              _isLoginFlow = true;
              _currentStep = 1;
            });
            _animateToNextStep();
          },
          isPrimary: false,
          icon: Icons.login,
        ),
        
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildPhoneNumberStep() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildStepHeader(
          title: _isLoginFlow ? 'Welcome Back!' : 'Verify Your Identity',
          subtitle: 'Enter your phone number to ${_isLoginFlow ? 'sign in' : 'continue registration'}',
          illustration: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  colorScheme.primary.withOpacity(0.1),
                  colorScheme.primary.withOpacity(0.05),
                  Colors.transparent,
                ],
                stops: const [0.3, 0.7, 1.0],
              ),
            ),
            child: Icon(
              Icons.phone_android,
              size: 48,
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
          child: IntlPhoneField(
            decoration: InputDecoration(
              labelText: 'Phone Number',
              hintText: 'Enter your phone number',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.all(20),
            ),
            initialCountryCode: 'US',
            onChanged: (phone) {
              setState(() {
                _fullPhoneNumber = phone.completeNumber;
              });
            },
          ),
        ),
        
        const SizedBox(height: 40),
        
        _buildModernButton(
          text: 'Send Verification Code',
          onPressed: !_isLoading && _fullPhoneNumber.isNotEmpty
              ? () async {
                  setState(() {
                    _isLoading = true;
                  });
                  try {
                    if (_isLoginFlow) {
                      await Provider.of<AuthProvider>(context, listen: false)
                          .sendSmsCode(_fullPhoneNumber, isLogin: true);
                    } else {
                      String username = _usernameController.text;
                      await Provider.of<AuthProvider>(context, listen: false)
                          .sendSmsCode(
                        _fullPhoneNumber,
                        isLogin: false,
                        username: username,
                      );
                    }
                    setState(() {
                      _currentStep = 2;
                    });
                    _animateToNextStep();
                  } catch (e) {
                    _showErrorDialog('Phone number invalid or does not have an active account.');
                  } finally {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                }
              : null,
          isPrimary: true,
          isLoading: _isLoading,
          icon: Icons.send,
        ),
        
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildVerifySmsStep() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildStepHeader(
          title: 'Enter Verification Code',
          subtitle: 'We sent a 6-digit code to $_fullPhoneNumber',
          illustration: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  colorScheme.primary.withOpacity(0.1),
                  colorScheme.primary.withOpacity(0.05),
                  Colors.transparent,
                ],
                stops: const [0.3, 0.7, 1.0],
              ),
            ),
            child: Icon(
              Icons.verified_user,
              size: 48,
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
            controller: _codeController,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: 'Verification Code',
              hintText: '000000',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.all(20),
              prefixIcon: Icon(
                Icons.lock_outline,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Debug info - can be removed later
        if (_codeController.text.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Code length: ${_codeController.text.trim().length}/6',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
        
        const SizedBox(height: 12),
        
        TextButton(
          onPressed: () async {
            try {
              if (_isLoginFlow) {
                await Provider.of<AuthProvider>(context, listen: false)
                    .sendSmsCode(_fullPhoneNumber, isLogin: true);
              } else {
                String username = _usernameController.text;
                await Provider.of<AuthProvider>(context, listen: false)
                    .sendSmsCode(
                  _fullPhoneNumber,
                  isLogin: false,
                  username: username,
                );
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Verification code resent'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            } catch (e) {
              _showErrorDialog('Failed to resend SMS code');
            }
          },
          child: Text(
            'Didn\'t receive a code? Resend',
            style: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        
        const SizedBox(height: 40),
        
        _buildModernButton(
          text: _isLoginFlow ? 'Sign In' : 'Complete Registration',
          onPressed: !_isLoading && _codeController.text.trim().length == 6
              ? _submitVerificationCode
              : null,
          isPrimary: true,
          isLoading: _isLoading,
          icon: _isLoginFlow ? Icons.login : Icons.check_circle,
        ),
        
        const SizedBox(height: 40),
      ],
    );
  }

  Future<void> _submitVerificationCode() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      if (_isLoginFlow) {
        await Provider.of<AuthProvider>(context, listen: false)
            .verifyLoginCode(
          _fullPhoneNumber,
          _codeController.text,
        );
        // Navigate to main app
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/main',
          (Route<dynamic> route) => false,
        );
      } else {
        String username = _usernameController.text;
        await Provider.of<AuthProvider>(context, listen: false)
            .verifyRegistrationCode(
          username,
          _fullPhoneNumber,
          _codeController.text,
        );
        // Navigate to main app
        Navigator.pushNamed(context, '/main');
      }
    } catch (e) {
      // Reset auto-submit flag on error so user can try again
      _hasAttemptedAutoSubmit = false;
      _showErrorDialog(_isLoginFlow ? 'Login failed' : 'Registration failed');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Error',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
              ),
              child: Text(
                'OK',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}