import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../screens/onboarding/welcome_screen.dart';
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
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    
    // Start simple fade in
    _fadeController.forward();
    
    _initializeApp();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }
  

  Future<void> _initializeApp() async {
    // Show splash for minimum time to ensure smooth UX
    await Future.delayed(const Duration(milliseconds: 1500));
    
    if (!mounted) return;
    
    // Check authentication state
    if (widget.client.isLogged()) {
      // User is logged in, go to main app
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MapTab(),
          transitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      // User not logged in, go directly to welcome screen
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => WelcomeScreen(),
          transitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  Widget _buildModernLogo() {
    return Container(
      width: 120,
      height: 120,
      child: Image.asset(
        'assets/logos/png-file-2.png',
        fit: BoxFit.contain,
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: _buildModernLogo(),
        ),
      ),
    );
  }
}