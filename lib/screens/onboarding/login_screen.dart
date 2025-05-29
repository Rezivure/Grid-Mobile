import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _homeserverController = TextEditingController();
  final _mapsUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  String? _errorMessage;
  bool _useDefaultMapsUrl = true;
  bool _obscurePassword = true;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _homeserverController.dispose();
    _mapsUrlController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = Provider.of<Client>(context, listen: false);
      final homeserver = _homeserverController.text.trim();
      String mapsUrl;

      if (_useDefaultMapsUrl) {
        mapsUrl = (dotenv.env['MAPS_URL'] ?? '').trim();
      } else {
        mapsUrl = _mapsUrlController.text.trim();
      }

      // Store the maps URL in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('maps_url', mapsUrl);

      await client.checkHomeserver(Uri.https(homeserver, ''));
      await client.login(
        LoginType.mLoginPassword,
        password: _passwordController.text,
        identifier: AuthenticationUserIdentifier(user: _usernameController.text),
      );

      setState(() {
        _isLoading = false;
      });

      // Store the custom homeserver URL for restoration
      await prefs.setString('custom_homeserver', homeserver);
      await prefs.setString('maps_url_type', _useDefaultMapsUrl ? 'default' : 'custom');
      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Login failed: ${e.toString()}';
      });
    }
  }

  Future<bool> _showLoginWarningDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Important Notice',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'If you use a homeserver that is also connected to other apps (like chat clients), your chat history could be wiped. Grid works best with a dedicated homeserver—don\'t mix and match.',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurface.withOpacity(0.7),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'I Understand, Continue',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Widget _buildModernLogo() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
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
      child: Image.asset(
        'assets/logos/png-file-2.png',
        height: 100,
        width: 100,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
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
        controller: controller,
        obscureText: obscureText,
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
          prefixIcon: Icon(
            icon,
            color: colorScheme.primary,
          ),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  Widget _buildMapsSelectionCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.map_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Maps Configuration',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Grid Maps Option
          GestureDetector(
            onTap: () {
              setState(() {
                _useDefaultMapsUrl = true;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _useDefaultMapsUrl 
                    ? colorScheme.primary.withOpacity(0.1)
                    : colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _useDefaultMapsUrl 
                      ? colorScheme.primary
                      : colorScheme.outline.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _useDefaultMapsUrl ? colorScheme.primary : Colors.transparent,
                      border: Border.all(
                        color: _useDefaultMapsUrl ? colorScheme.primary : colorScheme.outline,
                        width: 2,
                      ),
                    ),
                    child: _useDefaultMapsUrl
                        ? Icon(
                            Icons.check,
                            size: 12,
                            color: colorScheme.onPrimary,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grid Maps',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Use official Grid hosted map tiles',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Custom Maps Option
          GestureDetector(
            onTap: () {
              setState(() {
                _useDefaultMapsUrl = false;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: !_useDefaultMapsUrl 
                    ? colorScheme.primary.withOpacity(0.1)
                    : colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: !_useDefaultMapsUrl 
                      ? colorScheme.primary
                      : colorScheme.outline.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !_useDefaultMapsUrl ? colorScheme.primary : Colors.transparent,
                      border: Border.all(
                        color: !_useDefaultMapsUrl ? colorScheme.primary : colorScheme.outline,
                        width: 2,
                      ),
                    ),
                    child: !_useDefaultMapsUrl
                        ? Icon(
                            Icons.check,
                            size: 12,
                            color: colorScheme.onPrimary,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom Maps',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Use your own .pmtiles map source',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
                  color: colorScheme.onPrimary,
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
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
          'Custom Server',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  
                  // Modern Logo
                  _buildModernLogo(),
                  
                  const SizedBox(height: 24),
                  
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'ADVANCED LOGIN',
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
                    'Connect to Custom Server',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    'Sign in to your own Matrix homeserver with custom configuration',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 32),
                  
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Maps Selection
                  _buildMapsSelectionCard(),
                  
                  const SizedBox(height: 24),
                  
                  // Server URL
                  _buildModernTextField(
                    controller: _homeserverController,
                    label: 'Homeserver URL',
                    hint: 'matrix.example.com',
                    icon: Icons.dns_outlined,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Custom Maps URL (if selected)
                  if (!_useDefaultMapsUrl) ...[
                    _buildModernTextField(
                      controller: _mapsUrlController,
                      label: 'Custom Maps URL',
                      hint: 'https://example.com/maps.pmtiles',
                      icon: Icons.map_outlined,
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Username
                  _buildModernTextField(
                    controller: _usernameController,
                    label: 'Username',
                    hint: 'Enter your username',
                    icon: Icons.person_outline,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Password
                  _buildModernTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: colorScheme.primary,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Login Button
                  _buildModernButton(
                    text: 'Sign In',
                    onPressed: () async {
                      final confirmed = await _showLoginWarningDialog();
                      if (confirmed) {
                        await _login();
                      }
                    },
                    isPrimary: true,
                    isLoading: _isLoading,
                    icon: Icons.login,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Sign Up Button
                  _buildModernButton(
                    text: 'Don\'t have an account? Sign Up',
                    onPressed: () {
                      String mapsUrl;
                      if (_useDefaultMapsUrl) {
                        mapsUrl = (dotenv.env['MAPS_URL'] ?? '').trim();
                      } else {
                        mapsUrl = _mapsUrlController.text.trim();
                      }

                      Navigator.pushNamed(
                        context,
                        '/signup',
                        arguments: {
                          'homeserver': _homeserverController.text.trim(),
                          'mapsUrl': mapsUrl,
                        },
                      );
                    },
                    isPrimary: false,
                    icon: Icons.person_add,
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}