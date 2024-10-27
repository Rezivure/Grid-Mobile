import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _homeserverController = TextEditingController(text:  dotenv.env['HOMESERVER']); // Default homeserver
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mapsUrlController = TextEditingController(text:  dotenv.env['MAPS_URL']); // Default Maps URL
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = Provider.of<Client>(context, listen: false);
      final homeserver = _homeserverController.text.trim(); // Get homeserver from text field
      final mapsUrl = _mapsUrlController.text.trim(); // Get maps URL from text field

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

      await prefs.setString('serverType', 'custom');
      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Login failed: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background, // Use theme background color
      appBar: AppBar(
        leading: BackButton(color: colorScheme.onBackground), // Use theme color for back button
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView( // Make the content scrollable
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20), // Add some vertical padding
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(height: 20), // Add some space at the top
              Image.asset(
                'assets/logos/png-file-2.png', // Replace the lock icon with your logo
                height: 175, // Adjust the size as needed
              ),
              const SizedBox(height: 10),
              Text(
                'Sign In',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: colorScheme.primary, // Use primary color for text
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'Enter your details',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onBackground.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: TextStyle(color: colorScheme.error),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _homeserverController,
                decoration: InputDecoration(
                  labelText: 'Homeserver URL',
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: const UnderlineInputBorder(), // Line underneath
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _mapsUrlController,
                decoration: InputDecoration(
                  labelText: 'Maps URL (.pmtiles path)',
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: const UnderlineInputBorder(), // Line underneath
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: const UnderlineInputBorder(), // Line underneath
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: const UnderlineInputBorder(), // Line underneath
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? CircularProgressIndicator(color: colorScheme.primary)
                  : ElevatedButton(
                onPressed: _login,
                child: Text(
                  'Continue',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onPrimary, // Text color in the button
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary, // Button color
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
              const SizedBox(height: 5), // Add space between button and text button
              TextButton(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/signup',
                    arguments: {
                      'homeserver': _homeserverController.text, // Pass homeserver
                      'mapsUrl': _mapsUrlController.text, // Pass maps URL
                    },
                  );
                },
                child: Text(
                  'Don\'t have an account? Sign Up',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onBackground.withOpacity(0.7),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _homeserverController.dispose(); // Dispose of homeserver controller
    _mapsUrlController.dispose(); // Dispose of maps URL controller
    super.dispose();
  }
}
