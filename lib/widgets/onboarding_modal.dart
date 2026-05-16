import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:libre_location/libre_location.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../styles/tokens.dart';
import 'grid/grid_button.dart';
import 'grid/grid_mono.dart';

/// 2-step onboarding sheet shown the first time the user opens the map.
///
///   1. Welcome — Grid logo + value-prop one-liner + three privacy chips.
///   2. Permissions — banner hero, single screen, inline rows for Location
///      (required) and Motion (optional). Continue is enabled once
///      Location is granted; Not now closes without granting and
///      libre_location will re-prompt on the first sharing attempt.
///
/// Designed to fit on a single screen at any phone size — no scrolling.
class OnboardingModal extends StatefulWidget {
  final VoidCallback? onComplete;

  const OnboardingModal({Key? key, this.onComplete}) : super(key: key);

  @override
  _OnboardingModalState createState() => _OnboardingModalState();

  static Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding =
        prefs.getBool('has_seen_onboarding_v3') ?? false;
    return !hasSeenOnboarding;
  }

  static Future<void> showOnboardingIfNeeded(
    BuildContext context, {
    VoidCallback? onComplete,
  }) async {
    final shouldShow = await shouldShowOnboarding();
    if (shouldShow && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => OnboardingModal(onComplete: onComplete),
      );
    }
  }

  static Future<void> resetOnboardingPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('has_seen_onboarding_v2');
    await prefs.remove('has_seen_onboarding_v3');
  }
}

enum _PermState { idle, requesting, granted, deniedForever }

class _OnboardingModalState extends State<OnboardingModal>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final PageController _pageController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  int _currentPage = 0;
  _PermState _location = _PermState.idle;
  _PermState _motion = _PermState.idle;

  static const _pageCount = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _location == _PermState.deniedForever) {
      Future.delayed(
          const Duration(milliseconds: 400), _refreshLocationPermission);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _refreshLocationPermission() async {
    try {
      final p = await LibreLocation.checkPermission();
      if (!mounted) return;
      if (p == LocationPermission.always ||
          p == LocationPermission.whileInUse) {
        setState(() => _location = _PermState.granted);
      }
    } catch (_) {}
  }

  Future<void> _requestLocation() async {
    if (_location == _PermState.granted ||
        _location == _PermState.requesting) {
      return;
    }
    if (_location == _PermState.deniedForever) {
      openAppSettings();
      return;
    }
    setState(() => _location = _PermState.requesting);
    try {
      final permission = await LibreLocation.requestPermission();
      if (!mounted) return;
      switch (permission) {
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          setState(() => _location = _PermState.granted);
          return;
        case LocationPermission.denied:
          setState(() => _location = _PermState.idle);
          return;
        case LocationPermission.deniedForever:
          setState(() => _location = _PermState.deniedForever);
          return;
      }
    } catch (_) {
      if (mounted) setState(() => _location = _PermState.idle);
    }
  }

  Future<void> _requestMotion() async {
    if (_motion == _PermState.granted ||
        _motion == _PermState.requesting) {
      return;
    }
    setState(() => _motion = _PermState.requesting);
    try {
      if (Platform.isIOS) {
        // Briefly starting a tracking session is what triggers iOS to
        // surface the Motion & Fitness prompt — there's no standalone
        // request API in libre_location.
        await LibreLocation.start(
          preset: TrackingPreset.balanced,
          config: LocationConfig(
            backgroundPermissionRationale: PermissionRationale(
              title: 'Allow background location?',
              message:
                  'This app collects location data to enable real-time location sharing with your chosen contacts, even when not open.',
              positiveAction: 'Allow',
              negativeAction: 'Cancel',
            ),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        await LibreLocation.stop();
      }
      // On Android the OS bundles activity recognition with location;
      // marking as granted lets the UI reflect it.
      if (mounted) setState(() => _motion = _PermState.granted);
    } catch (_) {
      if (mounted) setState(() => _motion = _PermState.granted);
    }
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding_v3', true);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onComplete?.call();
  }

  void _onContinue() {
    if (_currentPage == 0) {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    } else {
      _complete();
    }
  }

  bool get _continueEnabled {
    if (_currentPage == 0) return true;
    return _location == _PermState.granted;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width > 380;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: media.padding.top + 16,
      ),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: media.size.height - (media.padding.top + 32),
            maxWidth: 460,
          ),
          decoration: BoxDecoration(
            color: GridTokens.surface,
            borderRadius: BorderRadius.circular(GridTokens.r2Xl),
            border: Border.all(color: GridTokens.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              _StepCounter(
                step: _currentPage + 1,
                total: _pageCount,
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _pageCount,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, index) {
                    if (index == 0) return _buildWelcomePage(isWide);
                    return _buildPermissionsPage();
                  },
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridButton(
            label: 'Continue',
            onPressed: _continueEnabled ? _onContinue : null,
          ),
          if (_currentPage == 1) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _complete,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: GridTokens.text3,
              ),
              child: Text(
                'Not now',
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: GridTokens.text3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Page 1: Welcome ────────────────────────────────────────────────

  Widget _buildWelcomePage(bool isWide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LogoHero(),
                const SizedBox(height: 22),
                Text(
                  'Welcome to Grid.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.025 * 26,
                    color: GridTokens.text,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Location sharing without compromise — encrypted, '
                  'private, on your own server if you want.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 14,
                    color: GridTokens.text2,
                    height: 1.45,
                    letterSpacing: -0.005,
                  ),
                ),
                const SizedBox(height: 16),
                const _BenefitChips(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Page 2: Permissions ────────────────────────────────────────────

  Widget _buildPermissionsPage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PermissionBanner(),
          const SizedBox(height: 22),
          Text(
            'Allow location',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.025 * 24,
              color: GridTokens.text,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'End-to-end encrypted. Only visible to people you add.',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 14,
              color: GridTokens.text2,
              height: 1.4,
              letterSpacing: -0.005,
            ),
          ),
          const SizedBox(height: 18),
          _PermissionRow(
            icon: Icons.location_on_rounded,
            iconColor: GridTokens.danger,
            iconBg: GridTokens.dangerSoft,
            title: 'Location',
            subtitle: 'Always',
            state: _location,
            requiredAction: true,
            onAllow: _requestLocation,
          ),
          const SizedBox(height: 10),
          _PermissionRow(
            icon: Icons.directions_run_rounded,
            iconColor: GridTokens.amber,
            iconBg: GridTokens.amberSoft,
            title: Platform.isIOS ? 'Motion & Fitness' : 'Motion',
            subtitle: 'Saves battery',
            state: _motion,
            requiredAction: false,
            onAllow: _requestMotion,
          ),
          const SizedBox(height: 14),
          _PrivacyPolicyLine(),
          const Spacer(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Page 2 hero — the mint banner block from the design mock
// ─────────────────────────────────────────────────────────────────────

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F5C4E),
            Color(0xFF1E8E76),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Faint dotted grid pattern — gives the banner texture without
          // pulling in a real illustration.
          Positioned.fill(
            child: CustomPaint(
              painter: _DotPainter(
                color: Colors.white.withOpacity(0.12),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.32),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.location_on_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 14.0;
    for (var y = 8.0; y < size.height; y += spacing) {
      for (var x = 8.0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────
// Permission row
// ─────────────────────────────────────────────────────────────────────

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.requiredAction,
    required this.onAllow,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final _PermState state;

  /// Required rows get a mint border in the granted state; optional rows
  /// stay neutral so they don't compete visually.
  final bool requiredAction;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final granted = state == _PermState.granted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: granted ? null : onAllow,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: GridTokens.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rLg),
            border: Border.all(
              color: granted && requiredAction
                  ? GridTokens.mint.withOpacity(0.5)
                  : GridTokens.hairline,
              width: granted && requiredAction ? 1.2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(GridTokens.rMd),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: GridTokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 12.5,
                        color: GridTokens.text2,
                        height: 1.3,
                        letterSpacing: -0.005,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RowTrailing(state: state, onAllow: onAllow),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowTrailing extends StatelessWidget {
  const _RowTrailing({required this.state, required this.onAllow});
  final _PermState state;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _PermState.granted:
        return const Icon(
          Icons.check_rounded,
          color: GridTokens.mint,
          size: 22,
        );
      case _PermState.requesting:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            color: GridTokens.mint,
            strokeWidth: 2,
          ),
        );
      case _PermState.deniedForever:
        return TextButton(
          onPressed: onAllow,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: GridTokens.amber,
          ),
          child: const Text(
            'Settings',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case _PermState.idle:
        return TextButton(
          onPressed: onAllow,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: GridTokens.mint,
          ),
          child: const Text(
            'Allow',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// Welcome hero + benefit chips + step counter
// ─────────────────────────────────────────────────────────────────────

class _LogoHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            GridTokens.mint.withOpacity(0.18),
            GridTokens.mint.withOpacity(0.05),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      alignment: Alignment.center,
      child: Image.asset(
        'assets/logos/png-file-2.png',
        width: 76,
        height: 76,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _BenefitChips extends StatelessWidget {
  const _BenefitChips();

  @override
  Widget build(BuildContext context) {
    final items = const [
      ('End-to-end encrypted', Icons.lock_outline_rounded),
      ('Only people you choose', Icons.shield_outlined),
      ('Open source', Icons.code_rounded),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (text, icon) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Chip(text: text, icon: icon),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: GridTokens.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: GridTokens.mint),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: GridTokens.text,
              letterSpacing: -0.005,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPolicyLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 12,
            color: GridTokens.text3,
            height: 1.4,
          ),
          children: [
            const TextSpan(text: 'Skeptical? Read our '),
            TextSpan(
              text: 'Privacy Policy',
              style: const TextStyle(
                color: GridTokens.mint,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  final uri = Uri.parse('https://mygrid.app/privacy');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                },
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}

class _StepCounter extends StatelessWidget {
  const _StepCounter({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: GridTokens.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: GridMono(
        'ONBOARDING · $step OF $total',
        size: 10,
        color: GridTokens.text2,
        letterSpacing: 0.12,
      ),
    );
  }
}
