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

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _slideController;
  late AnimationController _floatController;
  
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _floatAnimation;

  Timer? _avatarTimer;
  int _avatarUpdateIndex = 0;

  @override
  void initState() {
    super.initState();
    
    // Multiple animation controllers for staggered animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _floatAnimation = CurvedAnimation(
      parent: _floatController,
      curve: Curves.easeInOut,
    );

    // Start animations with staggered delays
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _scaleController.forward();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      _slideController.forward();
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      _floatController.repeat(reverse: true);
    });
    
    // Avatar animation timer
    _avatarTimer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      setState(() {
        _avatarUpdateIndex = DateTime.now().millisecondsSinceEpoch;
      });
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _slideController.dispose();
    _floatController.dispose();
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

  Widget _buildModernLogo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.1),
            Theme.of(context).colorScheme.primary.withOpacity(0.05),
            Colors.transparent,
          ],
          stops: const [0.3, 0.7, 1.0],
        ),
      ),
      child: Image.asset(
        'assets/logos/png-file-2.png',
        height: 120,
        width: 120,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildModernAvatarNetwork() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      width: 280,
      height: 180,
      child: AnimatedBuilder(
        animation: _floatAnimation,
        builder: (context, child) {
          return CustomPaint(
            painter: CircularLinesPainter(
              colorScheme: colorScheme,
              animationValue: _floatAnimation.value,
            ),
            child: Stack(
              children: _buildCircularAvatars(),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildCircularAvatars() {
    final double avatarSize = 35;
    final colorScheme = Theme.of(context).colorScheme;
    final double radius = 70;
    final center = Offset(140, 90); // Adjusted to fit all avatars within bounds
    
    // Create avatars in a circle (8 avatars for better visual balance)
    return List.generate(8, (i) {
      final angle = (i * 2 * pi / 8) - pi / 2; // Start from top, distribute evenly
      
      return AnimatedBuilder(
        animation: _floatAnimation,
        builder: (context, child) {
          // Add subtle floating animation
          final floatOffset = Offset(
            sin(_floatAnimation.value * 2 * pi + i * 0.5) * 2,
            cos(_floatAnimation.value * 2 * pi + i * 0.7) * 1.5,
          );
          
          // Calculate circular position
          final basePosition = Offset(
            center.dx + cos(angle) * radius,
            center.dy + sin(angle) * radius,
          );
          
          final animatedPosition = basePosition + floatOffset;
          
          return Positioned(
            left: animatedPosition.dx - avatarSize / 2,
            top: animatedPosition.dy - avatarSize / 2,
            child: AnimatedOpacity(
              opacity: 0.9,
              duration: const Duration(milliseconds: 500),
              child: Transform.scale(
                scale: 1.0 + sin(_floatAnimation.value * 2 * pi + i) * 0.03,
                child: Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.surface,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.2 + sin(_floatAnimation.value * 2 * pi + i) * 0.1),
                        blurRadius: 8 + sin(_floatAnimation.value * 2 * pi + i) * 2,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: RandomAvatar(
                      _avatarUpdateIndex.toString() + i.toString(),
                      height: avatarSize,
                      width: avatarSize,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildModernButton({
    required String text,
    required VoidCallback onPressed,
    required bool isPrimary,
    required ColorScheme colorScheme,
    IconData? icon,
  }) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isPrimary ? [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ] : null,
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? colorScheme.primary : Colors.transparent,
          foregroundColor: isPrimary ? colorScheme.onPrimary : colorScheme.primary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isPrimary ? BorderSide.none : BorderSide(
              color: colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
        ),
        child: Row(
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
                color: isPrimary ? colorScheme.onPrimary : colorScheme.primary,
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: <Widget>[
                const SizedBox(height: 20),
                
                // Modern Logo Section
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: _buildModernLogo(),
                  ),
                ),
                
                const SizedBox(height: 15),
                
                // Avatar Network
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: _buildModernAvatarNetwork(),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Welcome Text Section
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'WELCOME TO',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Grid',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontFamily: 'Goli',
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Connect with friends and share your location\nsecurely in real-time',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.7),
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Action Buttons
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        _buildModernButton(
                          text: 'Get Started',
                          onPressed: () {
                            Navigator.pushNamed(context, '/server_select');
                          },
                          isPrimary: true,
                          colorScheme: colorScheme,
                          icon: Icons.arrow_forward,
                        ),
                        const SizedBox(height: 12),
                        _buildModernButton(
                          text: 'Custom Provider',
                          onPressed: () {
                            Navigator.pushNamed(context, '/login');
                          },
                          isPrimary: false,
                          colorScheme: colorScheme,
                          icon: Icons.settings,
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Terms and Privacy
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Text.rich(
                      TextSpan(
                        text: 'By continuing, you agree to our ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                          height: 1.3,
                        ),
                        children: <TextSpan>[
                          TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                _launchUrl('https://mygrid.app/privacy');
                              },
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Terms of Service',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                _launchUrl('https://mygrid.app/terms');
                              },
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CircularLinesPainter extends CustomPainter {
  final ColorScheme colorScheme;
  final double animationValue;
  
  CircularLinesPainter({required this.colorScheme, required this.animationValue});
  
  @override
  void paint(Canvas canvas, Size size) {
    final double radius = 70;
    final center = Offset(140, 90);
    final int avatarCount = 8;
    
    // Subtle line settings
    final baseOpacity = 0.15 + sin(animationValue * 2 * pi) * 0.05;
    final paint = Paint()
      ..color = colorScheme.primary.withOpacity(baseOpacity)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    // Calculate avatar positions with floating animation
    List<Offset> avatarPositions = [];
    for (int i = 0; i < avatarCount; i++) {
      final angle = (i * 2 * pi / avatarCount) - pi / 2;
      
      final floatOffset = Offset(
        sin(animationValue * 2 * pi + i * 0.5) * 2,
        cos(animationValue * 2 * pi + i * 0.7) * 1.5,
      );
      
      final basePosition = Offset(
        center.dx + cos(angle) * radius,
        center.dy + sin(angle) * radius,
      );
      
      avatarPositions.add(basePosition + floatOffset);
    }
    
    // Draw lines connecting adjacent avatars
    for (int i = 0; i < avatarCount; i++) {
      final nextIndex = (i + 1) % avatarCount;
      final start = avatarPositions[i];
      final end = avatarPositions[nextIndex];
      
      // Add subtle animation delay for each connection
      final connectionAnimation = (animationValue + i * 0.1) % 1.0;
      final connectionOpacity = baseOpacity * (0.5 + sin(connectionAnimation * 2 * pi) * 0.3);
      
      final animatedPaint = Paint()
        ..color = colorScheme.primary.withOpacity(connectionOpacity)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      
      canvas.drawLine(start, end, animatedPaint);
    }
    
    // Optional: Draw lines to center for a more connected look
    for (int i = 0; i < avatarCount; i += 2) { // Only every other avatar to avoid clutter
      final start = avatarPositions[i];
      final connectionOpacity = baseOpacity * 0.3;
      
      final centerPaint = Paint()
        ..color = colorScheme.primary.withOpacity(connectionOpacity)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      
      canvas.drawLine(start, center, centerPaint);
    }
  }
  
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
