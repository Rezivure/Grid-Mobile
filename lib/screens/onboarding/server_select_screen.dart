import 'dart:async'; // Import for Timer
import 'dart:math'; // For generating random numbers
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

class ServerSelectScreen extends StatefulWidget {
  @override
  _ServerSelectScreenState createState() => _ServerSelectScreenState();
}

class _ServerSelectScreenState extends State<ServerSelectScreen> {
  int _currentStep = 0; // 0: Enter Username, 1: Enter Phone Number, 2: Verify SMS Code
  bool _isLoginFlow = false;
  bool _isLoading = false; // For showing spinner and disabling button

  // Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  // Variables for username availability
  String _usernameStatusMessage = '';
  Color _usernameStatusColor = Colors.transparent;

  Timer? _debounce; // Timer for debouncing input
  Timer? _typingTimer; // Timer for auto-typing username

  // Variable to store the full phone number
  String _fullPhoneNumber = '';

  @override
  void initState() {
    super.initState();

    // Add listeners to username controller to check username availability
    _usernameController.addListener(_onUsernameChanged);
  }


  void _onUsernameChanged() {
    // Debounce input to prevent rapid validation calls
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _validateUsernameInput();
    });
  }

  void _validateUsernameInput() {
    String username = _usernameController.text;

    // Ensure that the text part of the username is at least 5 characters
    if (username.length < 5) {
      setState(() {
        _usernameStatusMessage =
        'Username must be at least 5 characters and no special characters or spaces.';
        _usernameStatusColor = Colors.red;
      });
      return;
    }

    // If input is valid, proceed with async username availability check
    _checkUsernameAvailability();
  }

  Future<void> _checkUsernameAvailability() async {
    String username = _usernameController.text;

    // Check availability only if username is valid
    if (username.isNotEmpty && username.length >= 5) {
      // Call the AuthProvider to check availability
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

  @override
  void dispose() {
    _usernameController.dispose();
    _codeController.dispose();
    _debounce?.cancel(); // Cancel debounce timer if any
    _typingTimer?.cancel(); // Cancel typing timer
    super.dispose();
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
        child: _buildCurrentStep(context),
      ),
    );
  }

  Widget _buildCurrentStep(BuildContext context) {
    switch (_currentStep) {
      case 0:
        return _buildUsernameStep(context);
      case 1:
        return _buildPhoneNumberStep(context);
      case 2:
        return _buildVerifySmsStep(context);
      default:
        return Container();
    }
  }

  Widget _buildUsernameStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String username = _usernameController.text.isNotEmpty
        ? _usernameController.text
        : 'default';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 50),
          Text(
            'Set a Username',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: colorScheme.primary,
            ),
          ),
          Text(
            'This is how others can discover you.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onBackground.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 20),
          RandomAvatar(
            username.toLowerCase(),
            height: 100,
            width: 100,
          ),
          const SizedBox(height: 10),
          Text(
            'This will be your avatar!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onBackground.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: colorScheme.surface.withOpacity(0.1),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _usernameStatusMessage,
            style: TextStyle(color: _usernameStatusColor),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: (_usernameStatusMessage == 'Username is available') && !_isLoading
                ? () {
              setState(() {
                _currentStep = 1; // Proceed to next step
              });
            }
                : null, // Disable button if username is not available or loading
            child: _isLoading ? CircularProgressIndicator(color: colorScheme.onPrimary) : Text(
              'Next',
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
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _isLoginFlow = true;
                _currentStep = 1; // Go to phone number step for login
              });
            },
            child: Text(
              'Already have an account? Sign in',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.secondary, // Secondary color
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneNumberStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Lottie.network(
            'https://lottie.host/e8ebf51a-dd5f-4b40-8320-ca08f5041d13/LNsJZ0BVrk.json',
            height: 150,
            width: 150,
          ),
          const SizedBox(height: 20),
          Text(
            _isLoginFlow ? 'Sign In' : 'Register',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Please enter your phone number to confirm your identity.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onBackground.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          IntlPhoneField(
            decoration: InputDecoration(
              labelText: 'Phone Number',
              border: OutlineInputBorder(
                borderSide: BorderSide(),
              ),
              filled: true,
              fillColor: colorScheme.surface.withOpacity(0.1),
            ),
            initialCountryCode: 'US',
            onChanged: (phone) {
              setState(() {
                _fullPhoneNumber = phone.completeNumber;
              });
              print('Full phone number: $_fullPhoneNumber');
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: !_isLoading
                ? () async {
              setState(() {
                _isLoading = true;
              });
              try {
                if (_fullPhoneNumber.isEmpty) {
                  _showErrorDialog(context, 'Please enter a valid phone number.');
                  setState(() {
                    _isLoading = false;
                  });
                  return;
                }
                if (_isLoginFlow) {
                  // For login, only phone number is required
                  await Provider.of<AuthProvider>(context, listen: false)
                      .sendSmsCode(_fullPhoneNumber, isLogin: true);
                } else {
                  // For registration, both username and phone number are required
                  String username = _usernameController.text;
                  await Provider.of<AuthProvider>(context, listen: false)
                      .sendSmsCode(
                    _fullPhoneNumber,
                    isLogin: false,
                    username: username,
                  );
                }
                setState(() {
                  _currentStep = 2; // Proceed to verify code step
                });
              } catch (e) {
                _showErrorDialog(context, 'Phone number invalid or already registered');
              } finally {
                setState(() {
                  _isLoading = false;
                });
              }
            }
                : null, // Disable button if loading
            child: _isLoading ? CircularProgressIndicator(color: colorScheme.onPrimary) : Text(
              'Send Code',
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
        ],
      ),
    );
  }

  Widget _buildVerifySmsStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const SizedBox(height: 20),
          Lottie.network(
            'https://lottie.host/e8ebf51a-dd5f-4b40-8320-ca08f5041d13/LNsJZ0BVrk.json',
            height: 150,
            width: 150,
          ),
          const SizedBox(height: 20),
          Text(
            'Enter Verification Code',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () async {
              try {
                if (_fullPhoneNumber.isEmpty) {
                  _showErrorDialog(context, 'Please enter a valid phone number.');
                  return;
                }
                if (_isLoginFlow) {
                  // For login, only phone number is required
                  await Provider.of<AuthProvider>(context, listen: false)
                      .sendSmsCode(_fullPhoneNumber, isLogin: true);
                } else {
                  // For registration, both username and phone number are required
                  String username = _usernameController.text;
                  await Provider.of<AuthProvider>(context, listen: false)
                      .sendSmsCode(
                    _fullPhoneNumber,
                    isLogin: false,
                    username: username,
                  );
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Verification code resent')),
                );
              } catch (e) {
                _showErrorDialog(context, 'Failed to resend SMS code');
              }
            },
            child: Text(
              'Resend code?',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary.withOpacity(0.8),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Verification Code',
              border: OutlineInputBorder(
                borderSide: BorderSide(),
              ),
              filled: true,
              fillColor: colorScheme.surface.withOpacity(0.1),
              hintText: 'Enter your 6-digit code',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: !_isLoading
                ? () async {
              setState(() {
                _isLoading = true;
              });
              if (_codeController.text.length == 6) {
                if (_fullPhoneNumber.isEmpty) {
                  _showErrorDialog(context, 'Please enter a valid phone number.');
                  setState(() {
                    _isLoading = false;
                  });
                  return;
                }
                if (_isLoginFlow) {
                  // Login flow
                  try {
                    await Provider.of<AuthProvider>(context, listen: false)
                        .verifyLoginCode(
                      _fullPhoneNumber,
                      _codeController.text,
                    );
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/main',      // The target route (main screen)
                          (Route<dynamic> route) => false,  // Remove all previous routes
                    );
                  } catch (e) {
                    _showErrorDialog(context, 'Login failed');
                  }
                } else {
                  // Register flow
                  String username = _usernameController.text;
                  try {
                    await Provider.of<AuthProvider>(context, listen: false)
                        .verifyRegistrationCode(
                      username,
                      _fullPhoneNumber,
                      _codeController.text,
                    );
                    Navigator.pushNamed(context, '/main');
                  } catch (e) {
                    _showErrorDialog(context, 'Registration failed');
                  }
                }
              } else {
                _showInvalidCodeDialog(context);
              }
              setState(() {
                _isLoading = false;
              });
            }
                : null, // Disable button if loading
            child: _isLoading ? CircularProgressIndicator(color: colorScheme.onPrimary) : Text(
              _isLoginFlow ? 'Sign In' : 'Register',
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
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showInvalidCodeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Invalid Code'),
          content: Text('Please enter a valid 6-digit verification code.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
