import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:math';

class WelcomeScreen extends StatefulWidget {
  @override
  _WelcomeScreenState createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  Timer? _avatarTimer;
  int _avatarUpdateIndex = 0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
    _avatarTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      setState(() {
        _avatarUpdateIndex = DateTime.now().millisecondsSinceEpoch;
      });
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _avatarTimer?.cancel();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(height: 60), // Replace Spacer
              FadeTransition(
                opacity: _fadeAnimation,
                child: Image.asset(
                  'assets/logos/png-file-2.png',
                  height: 250,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 250,
                height: 250,
                padding: const EdgeInsets.all(0),
                child: Stack(
                  alignment: Alignment.center,
                  children: _buildAvatarCircle(),
                ),
              ),
              const SizedBox(height: 30), // Replace Spacer
              FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  'Welcome to Grid',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  '',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onBackground.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Text.rich(
                  TextSpan(
                    text: 'By using this app, you agree to our\n ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onBackground.withOpacity(0.6),
                    ),
                    children: <TextSpan>[
                      TextSpan(
                        text: 'Privacy Policy',
                        style: TextStyle(
                          color: colorScheme.primary,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            _launchUrl('https://mygrid.app/privacy');
                          },
                      ),
                      TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Terms of Service.',
                        style: TextStyle(
                          color: colorScheme.primary,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            _launchUrl('https://mygrid.app/terms');
                          },
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30), // Replace Spacer
              FadeTransition(
                opacity: _fadeAnimation,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/server_select');
                  },
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
              ),
              const SizedBox(height: 10),
              FadeTransition(
                opacity: _fadeAnimation,
                child: TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/login');
                  },
                  child: Text(
                    'Custom Provider',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.secondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAvatarCircle() {
    final double radius = 100;
    final int avatarCount = 10;
    final double avatarSize = 40;
    final double angleIncrement = (2 * pi) / avatarCount;
    final double offsetX = 20;
    final double offsetY = 20;

    List<Widget> avatars = [];
    for (int i = 0; i < avatarCount; i++) {
      final double angle = i * angleIncrement;
      final double x = radius * cos(angle) + offsetX;
      final double y = radius * sin(angle) + offsetY;

      avatars.add(
        Positioned(
          left: x + radius - avatarSize / 2,
          top: y + radius - avatarSize / 2,
          child: RandomAvatar(
            _avatarUpdateIndex.toString() + i.toString(),
            height: avatarSize,
            width: avatarSize,
          ),
        ),
      );
    }

    return avatars;
  }
}