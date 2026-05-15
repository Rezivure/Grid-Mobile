import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:math';

import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';

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
      if (mounted) _scaleController.forward();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _slideController.forward();
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _floatController.repeat(reverse: true);
    });
    
    // Avatar animation timer
    _avatarTimer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (mounted) {
        setState(() {
          _avatarUpdateIndex = DateTime.now().millisecondsSinceEpoch;
        });
      }
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
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // 8-avatar constellation hero.
              FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: const _AvatarConstellation(),
                ),
              ),
              const Spacer(flex: 2),
              // E2E ENCRYPTED · OPEN SOURCE chip
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: GridTokens.mintFaint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: GridTokens.mint,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: GridTokens.mint.withOpacity(0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const GridMono(
                        'E2E ENCRYPTED · OPEN SOURCE',
                        color: GridTokens.mint,
                        size: 10,
                        letterSpacing: 0.08,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  'Be hard to track.',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.03,
                    color: GridTokens.text,
                    height: 1.05,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              FadeTransition(
                opacity: _fadeAnimation,
                child: SizedBox(
                  width: 300,
                  child: Text(
                    'Share your location only with the people you choose — encrypted, on your own infrastructure if you want.',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: GridTokens.text2,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const Spacer(flex: 3),
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      GridButton(
                        label: 'Get started',
                        onPressed: () =>
                            Navigator.pushNamed(context, '/server_select'),
                      ),
                      const SizedBox(height: 8),
                      GridButton(
                        label: 'I already have an account',
                        style: GridButtonStyle.ghost,
                        onPressed: () {
                          // The same multi-step screen handles both flows;
                          // the login-flow flag is set inside.
                          Navigator.pushNamed(
                            context,
                            '/server_select',
                            arguments: {'isLoginFlow': true},
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    Text.rich(
                      TextSpan(
                        text: 'By continuing you agree to our ',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 11.5,
                          color: GridTokens.text3,
                        ),
                        children: [
                          TextSpan(
                            text: 'Terms & Privacy',
                            style: TextStyle(
                              color: GridTokens.text2,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap =
                                  () => _launchUrl('https://mygrid.app/privacy'),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: GridTokens.mint,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.link_rounded, size: 14, color: GridTokens.mint),
                          SizedBox(width: 4),
                          Text(
                            'Use a custom server',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: GridTokens.mint,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// 8-avatar constellation rendered in a fixed-size canvas.
/// Avatar colors are drawn from a deterministic palette so it always reads
/// as the same image across launches.
class _AvatarConstellation extends StatelessWidget {
  const _AvatarConstellation();

  static const _palette = <List<Color>>[
    [Color(0xFF7DD181), Color(0xFF2F6B33)], // A — green
    [Color(0xFF00DBA4), Color(0xFF0F7B5E)], // M — mint
    [Color(0xFFF5B947), Color(0xFF8A5E15)], // D — amber
    [Color(0xFFFF8E72), Color(0xFF8A3F2A)], // K — coral
    [Color(0xFFB79EFF), Color(0xFF5B4690)], // J — purple
    [Color(0xFF6DD3F5), Color(0xFF1F6E8F)], // S — sky
    [Color(0xFFE879C1), Color(0xFF7B2E60)], // R — pink
    [Color(0xFF9DC3FF), Color(0xFF34619D)], // Y — blue
  ];
  static const _letters = ['A', 'M', 'D', 'K', 'J', 'S', 'R', 'Y'];

  @override
  Widget build(BuildContext context) {
    const size = 280.0;
    const r = 95.0;
    const avatarSize = 44.0;

    final positions = <Offset>[];
    for (var i = 0; i < 8; i++) {
      final angle = (i * 2 * pi / 8) - pi / 2;
      positions.add(Offset(
        size / 2 + r * cos(angle),
        size / 2 + r * sin(angle),
      ));
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: const Size(size, size),
            painter: _ConstellationLines(positions: positions),
          ),
          // Outer dashed ring
          Center(
            child: Container(
              width: 246,
              height: 246,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: GridTokens.mint.withOpacity(0.18),
                  width: 1,
                ),
              ),
            ),
          ),
          // Inner solid ring
          Center(
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: GridTokens.mint.withOpacity(0.22),
                  width: 1,
                ),
              ),
            ),
          ),
          // Center Grid mark
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: GridTokens.mintFaint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: GridTokens.mint.withOpacity(0.3),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: GridTokens.mint,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          // Avatars
          for (var i = 0; i < positions.length; i++)
            Positioned(
              left: positions[i].dx - avatarSize / 2,
              top: positions[i].dy - avatarSize / 2,
              child: _ConstellationAvatar(
                letter: _letters[i],
                palette: _palette[i],
              ),
            ),
        ],
      ),
    );
  }
}

class _ConstellationAvatar extends StatelessWidget {
  const _ConstellationAvatar({required this.letter, required this.palette});

  final String letter;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 0.95,
          colors: palette,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: GridTokens.bg, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: GoogleFonts.getFont(
          'Geist',
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
      ),
    );
  }
}

class _ConstellationLines extends CustomPainter {
  _ConstellationLines({required this.positions});
  final List<Offset> positions;

  @override
  void paint(Canvas canvas, Size size) {
    final connector = Paint()
      ..color = GridTokens.mint.withOpacity(0.18)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < positions.length; i++) {
      final j = (i + 1) % positions.length;
      canvas.drawLine(positions[i], positions[j], connector);
    }
    final cross = Paint()
      ..color = GridTokens.mint.withOpacity(0.10)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < positions.length; i += 2) {
      final j = (i + 4) % positions.length;
      canvas.drawLine(positions[i], positions[j], cross);
    }
  }

  @override
  bool shouldRepaint(_ConstellationLines old) =>
      old.positions != positions;
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
