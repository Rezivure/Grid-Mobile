import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:math';

import 'package:grid_frontend/styles/grid_colors.dart';
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
        'assets/brand/01-logos/grid-symbol-color-1024.png',
        height: 120,
        width: 120,
        fit: BoxFit.contain,
      ),
    );
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
              // Grid logo hero.
              FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.85,
                        colors: [
                          context.gridColors.mint.withOpacity(0.16),
                          context.gridColors.mint.withOpacity(0.06),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Image.asset(
                      'assets/brand/01-logos/grid-symbol-color-1024.png',
                      width: 132,
                      height: 132,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 2),
              // E2E ENCRYPTED · OPEN SOURCE chip
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.gridColors.mintFaint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: context.gridColors.mint,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: context.gridColors.mint.withOpacity(0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      GridMono(
                        'E2E ENCRYPTED · OPEN SOURCE',
                        color: context.gridColors.mint,
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
                    color: context.gridColors.text,
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
                    'Share your location only with the people you choose. End-to-end encrypted by default.',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: context.gridColors.text2,
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
                          color: context.gridColors.text3,
                        ),
                        children: [
                          TextSpan(
                            text: 'Terms & Privacy',
                            style: TextStyle(
                              color: context.gridColors.text2,
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
                        foregroundColor: context.gridColors.mint,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_rounded, size: 14, color: context.gridColors.mint),
                          SizedBox(width: 4),
                          Text(
                            'Use a custom server',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.gridColors.mint,
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
                  color: context.gridColors.mint.withOpacity(0.18),
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
                  color: context.gridColors.mint.withOpacity(0.22),
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
                color: context.gridColors.mintFaint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: context.gridColors.mint.withOpacity(0.3),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: context.gridColors.mint,
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
        border: Border.all(color: context.gridColors.bg, width: 2),
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
      ..color = const Color(0xFF00DBA4).withOpacity(0.18)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < positions.length; i++) {
      final j = (i + 1) % positions.length;
      canvas.drawLine(positions[i], positions[j], connector);
    }
    final cross = Paint()
      ..color = const Color(0xFF00DBA4).withOpacity(0.10)
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

