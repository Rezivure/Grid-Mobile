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
  final _homeserverController = TextEditingController();
  final _mapsUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  bool _useDefaultMapsUrl = true; // Default is to use the default maps URL

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
        identifier:
        AuthenticationUserIdentifier(user: _usernameController.text),
      );

      setState(() {
        _isLoading = false;
      });

      await prefs.setString(
          'maps_url_type', _useDefaultMapsUrl ? 'default' : 'custom');
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
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        leading: BackButton(color: colorScheme.onBackground),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(height: 20),
              Image.asset(
                'assets/logos/png-file-2.png',
                height: 175,
              ),
              const SizedBox(height: 10),
              Text(
                'Sign In',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: colorScheme.primary,
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
              // Radio buttons for Default and Custom Maps URL (moved above input boxes)
              Column(
                children: [
                  ListTile(
                    title: const Text('Grid Maps'),
                    leading: Radio<bool>(
                      value: true,
                      groupValue: _useDefaultMapsUrl,
                      onChanged: (bool? value) {
                        setState(() {
                          _useDefaultMapsUrl = value!;
                        });
                      },
                    ),
                  ),
                  ListTile(
                    title: const Text('Custom Maps'),
                    leading: Radio<bool>(
                      value: false,
                      groupValue: _useDefaultMapsUrl,
                      onChanged: (bool? value) {
                        setState(() {
                          _useDefaultMapsUrl = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _homeserverController,
                decoration: InputDecoration(
                  labelText: 'Homeserver URL',
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: const UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              if (!_useDefaultMapsUrl) ...[
                TextField(
                  controller: _mapsUrlController,
                  decoration: InputDecoration(
                    labelText: 'Maps URL (.pmtiles path)',
                    filled: true,
                    fillColor: colorScheme.surface,
                    border: const UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: const UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: const UnderlineInputBorder(),
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
                    color: colorScheme.onPrimary,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              TextButton(
                onPressed: () {
                  // Get the latest mapsUrl value based on user's selection
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
    _homeserverController.dispose();
    _mapsUrlController.dispose();
    super.dispose();
  }
}
