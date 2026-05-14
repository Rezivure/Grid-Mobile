import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../screens/onboarding/welcome_screen.dart';
import '../screens/onboarding/splash_screen.dart';
import '../screens/map/map_tab.dart';

class AppInitializer extends StatefulWidget {
  final Client client;

  const AppInitializer({Key? key, required this.client}) : super(key: key);

  @override
  _AppInitializerState createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    // Simple fade and scale animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    
    // Start simple fade in
    _fadeController.forward();
    
    // Schedule initialization after the current frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }
  

  Future<void> _initializeApp() async {
    // Add a minimal delay to ensure the widget is fully built
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted) return;
    
    // Check authentication state
    if (widget.client.isLogged()) {
      // User is logged in, go directly to main app (no splash screen)
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MapTab(),
          transitionDuration: const Duration(milliseconds: 150),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      // User not logged in, go directly to welcome screen (no custom splash)
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => WelcomeScreen(),
          transitionDuration: const Duration(milliseconds: 150),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show nothing - just an empty container while we check auth
    // The native splash will still be showing
    return Container(
      color: colorScheme.surface,
    );
  }
}