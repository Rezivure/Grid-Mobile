import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:random_avatar/random_avatar.dart';

class SignUpScreen extends StatefulWidget {
  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> with TickerProviderStateMixin {
  late String _homeserver;
  late String _mapsUrl;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    
    _fadeController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Retrieve the homeserver and mapsUrl passed from the previous screen
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>? ?? {};
    _homeserver = args['homeserver'] ?? 'matrix-dev.mygrid.app';
    _mapsUrl = args['mapsUrl'] ?? 'https://example.com/tiles.pmtiles';

    // Add listener to update the avatar dynamically as the user types
    _usernameController.addListener(() {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // Header with back button
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back,
                        color: colorScheme.onSurface,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Step 2 of 2',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 40),
                
                // Avatar Section
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colorScheme.outline.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: RandomAvatar(
                          _usernameController.text.isNotEmpty 
                              ? _usernameController.text.toLowerCase() 
                              : 'default',
                          height: 100,
                          width: 100,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your Avatar Preview',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This unique avatar is generated from your username',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Main Form Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create Account',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set up your Grid account with a unique username',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Server Info Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _homeserver.isEmpty 
                              ? colorScheme.errorContainer.withOpacity(0.3)
                              : colorScheme.surfaceVariant.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _homeserver.isEmpty 
                                ? colorScheme.error.withOpacity(0.3)
                                : colorScheme.outline.withOpacity(0.1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _homeserver.isEmpty ? Icons.error_outline : Icons.dns_outlined,
                                  size: 20,
                                  color: _homeserver.isEmpty ? colorScheme.error : colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Server Configuration',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: _homeserver.isEmpty ? colorScheme.error : colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildServerInfoRow(
                              'Homeserver', 
                              _homeserver.isEmpty ? 'No homeserver set' : _homeserver, 
                              Icons.home_outlined,
                              isError: _homeserver.isEmpty,
                            ),
                            const SizedBox(height: 8),
                            _buildServerInfoRow(
                              'Maps Provider', 
                              _mapsUrl.contains('mygrid.app') ? 'Grid Maps' : _mapsUrl, 
                              Icons.map_outlined
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Error Message
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: colorScheme.onErrorContainer,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Username Field
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          hintText: 'Enter your unique username',
                          prefixIcon: Container(
                            width: 40,
                            alignment: Alignment.center,
                            child: Text(
                              '@',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          hintText: 'Create a secure password',
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: colorScheme.primary,
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Password Helper Text
                      Text(
                        'Make sure to remember your password - it can\'t be recovered!',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Sign Up Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            disabledBackgroundColor: colorScheme.surfaceVariant,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      colorScheme.onPrimary,
                                    ),
                                  ),
                                )
                              : Text(
                                  'Create Account',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Sign In Link
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              '/login',
                              arguments: {
                                'homeserver': _homeserver,
                                'mapsUrl': _mapsUrl,
                              },
                            );
                          },
                          child: RichText(
                            text: TextSpan(
                              text: 'Already have an account? ',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.7),
                              ),
                              children: [
                                TextSpan(
                                  text: 'Sign In',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerInfoRow(String label, String value, IconData icon, {bool isError = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isError 
              ? colorScheme.error 
              : colorScheme.onSurface.withOpacity(0.6),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: isError 
                ? colorScheme.error 
                : colorScheme.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isError 
                  ? colorScheme.error 
                  : colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _signUp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Username and password cannot be empty';
        _isLoading = false;
      });
      return;
    }

    final client = Provider.of<Client>(context, listen: false);

    try {
      // Ensure the client is logged out before attempting to register a new user
      if (client.isLogged()) {
        await client.logout();
      }

      await client.checkHomeserver(Uri.https(_homeserver.trim(), ''));

      await _registerUser(client, username, password);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to sign up: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _registerUser(Client client, String username, String password) async {
    try {
      final response = await client.register(
        kind: AccountKind.user,
        username: username,
        password: password,
        auth: null,
        deviceId: null,
        initialDeviceDisplayName: 'Grid App Device',
        inhibitLogin: false,
        refreshToken: true,
      );

      if (response.accessToken == null || response.userId == null) {
        throw Exception('Access token or user ID is null after registration.');
      }

      await _saveToken(response.accessToken!, response.userId!);

      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      if (e is MatrixException && e.errcode == 'M_FORBIDDEN') {
        await _handleAdditionalAuth(client, username, password, e.session);
      } else {
        setState(() {
          _errorMessage = 'Failed to sign up: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleAdditionalAuth(Client client, String username, String password, String? session) async {
    try {
      final authData = AuthenticationData(
        type: 'm.login.dummy',
        session: session,
      );

      final response = await client.register(
        kind: AccountKind.user,
        username: username,
        password: password,
        auth: authData,
        deviceId: null,
        initialDeviceDisplayName: 'Grid App Device',
        inhibitLogin: false,
        refreshToken: true,
      );

      if (response.accessToken == null || response.userId == null) {
        throw Exception('Access token or user ID is null after registration.');
      }

      await _saveToken(response.accessToken!, response.userId!);

      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to sign up: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveToken(String token, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
    await prefs.setString('user_id', userId);
    
    // Store the custom homeserver URL for restoration
    await prefs.setString('custom_homeserver', _homeserver);
    await prefs.setString('maps_url', _mapsUrl); // Save the map tile URL
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}