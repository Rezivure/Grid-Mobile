import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:libre_location/libre_location.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../styles/tokens.dart';
import 'grid/grid_button.dart';

/// 3-step onboarding sheet shown the first time the user opens the map.
///
/// Replaces the previous 8-card carousel. The whole flow is now:
///   1. Welcome — logo, value-prop one-liner, three privacy chips.
///   2. Location — single page that owns the permission request. The CTA
///      morphs through `Allow location → Requesting… → Allowed` and
///      auto-advances the moment iOS/Android returns a grant. Denial
///      surfaces an inline Settings link instead of bouncing the user to
///      a snackbar.
///   3. Ready — single "Open Grid" button that closes the modal.
///
/// Motion / Activity permission is intentionally NOT a separate card.
/// `libre_location` requests it implicitly the first time `start()` is
/// called, which is well after onboarding finishes, so adding a second
/// "tap me" card here just added friction with no real signal.
class OnboardingModal extends StatefulWidget {
  final VoidCallback? onComplete;

  const OnboardingModal({Key? key, this.onComplete}) : super(key: key);

  @override
  _OnboardingModalState createState() => _OnboardingModalState();

  static Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    // v3 flag — bumped after redesigning the modal to a 3-step flow so
    // existing v2-marked users see the new flow once.
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding_v3') ?? false;
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

enum _PermissionState { idle, requesting, granted, deniedForever }

class _OnboardingModalState extends State<OnboardingModal>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final PageController _pageController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  int _currentPage = 0;
  _PermissionState _permission = _PermissionState.idle;

  static const _pageCount = 3;

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
    // If the user left to grant permission in Settings, re-check on return.
    if (state == AppLifecycleState.resumed &&
        _permission == _PermissionState.deniedForever) {
      Future.delayed(const Duration(milliseconds: 400), _refreshPermission);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _refreshPermission() async {
    try {
      final p = await LibreLocation.checkPermission();
      if (!mounted) return;
      if (p == LocationPermission.always ||
          p == LocationPermission.whileInUse) {
        setState(() => _permission = _PermissionState.granted);
        _advanceFromLocationPage();
      }
    } catch (_) {}
  }

  Future<void> _requestLocation() async {
    setState(() => _permission = _PermissionState.requesting);
    try {
      final permission = await LibreLocation.requestPermission();
      if (!mounted) return;
      switch (permission) {
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          setState(() => _permission = _PermissionState.granted);
          _advanceFromLocationPage();
          return;
        case LocationPermission.denied:
          // Soft denial — leave them on the page so they can tap again.
          setState(() => _permission = _PermissionState.idle);
          return;
        case LocationPermission.deniedForever:
          setState(() => _permission = _PermissionState.deniedForever);
          return;
      }
    } catch (_) {
      if (mounted) setState(() => _permission = _PermissionState.idle);
    }
  }

  void _advanceFromLocationPage() {
    // Brief pause so the user sees the "Allowed" success state before the
    // page transitions to the final "Open Grid" step.
    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _pageController.animateToPage(
        2,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding_v3', true);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onComplete?.call();
  }

  void _onPrimaryPressed() {
    switch (_currentPage) {
      case 0:
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
        break;
      case 1:
        if (_permission == _PermissionState.deniedForever) {
          openAppSettings();
          return;
        }
        if (_permission == _PermissionState.granted) {
          _advanceFromLocationPage();
          return;
        }
        if (_permission != _PermissionState.requesting) {
          _requestLocation();
        }
        break;
      case 2:
        _complete();
        break;
    }
  }

  String get _primaryLabel {
    switch (_currentPage) {
      case 0:
        return 'Continue';
      case 1:
        switch (_permission) {
          case _PermissionState.idle:
            return 'Allow location';
          case _PermissionState.requesting:
            return 'Requesting…';
          case _PermissionState.granted:
            return 'Allowed';
          case _PermissionState.deniedForever:
            return 'Open Settings';
        }
      case 2:
      default:
        return 'Open Grid';
    }
  }

  IconData? get _primaryIcon {
    switch (_currentPage) {
      case 1:
        switch (_permission) {
          case _PermissionState.idle:
            return Icons.location_on_rounded;
          case _PermissionState.granted:
            return Icons.check_rounded;
          case _PermissionState.deniedForever:
            return Icons.open_in_new_rounded;
          case _PermissionState.requesting:
            return null;
        }
      case 2:
        return Icons.arrow_forward_rounded;
      default:
        return null;
    }
  }

  bool get _primaryEnabled {
    if (_currentPage == 1 &&
        _permission == _PermissionState.requesting) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: media.padding.top + 24,
      ),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: media.size.height - (media.padding.top + 48),
          ),
          decoration: BoxDecoration(
            color: GridTokens.bg,
            borderRadius: BorderRadius.circular(GridTokens.r2Xl),
            border: Border.all(color: GridTokens.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              _PageDots(active: _currentPage, count: _pageCount),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _pageCount,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, index) {
                    switch (index) {
                      case 0:
                        return _buildWelcomePage();
                      case 1:
                        return _buildLocationPage();
                      case 2:
                      default:
                        return _buildReadyPage();
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  children: [
                    GridButton(
                      label: _primaryLabel,
                      icon: _primaryIcon,
                      onPressed: _primaryEnabled ? _onPrimaryPressed : null,
                    ),
                    if (_currentPage == 1 &&
                        _permission != _PermissionState.granted) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _complete,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: GridTokens.text3,
                        ),
                        child: Text(
                          'I\'ll do this later',
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pages ──────────────────────────────────────────────────────────

  Widget _buildWelcomePage() {
    return _StepLayout(
      hero: _LogoHero(),
      title: 'Welcome to Grid.',
      body: 'Location sharing without compromise — encrypted, private, on '
          'your own server if you want.',
      extras: const _BenefitChips(),
    );
  }

  Widget _buildLocationPage() {
    String body;
    Widget? extras;
    switch (_permission) {
      case _PermissionState.deniedForever:
        body =
            'iOS is blocking the location prompt. Open Settings, set Grid '
            'to Always, then come back here.';
        extras = const SizedBox.shrink();
        break;
      case _PermissionState.granted:
        body =
            'Always-on lets friends see your dot move even when the app is '
            'closed. Nothing leaves your phone unencrypted.';
        extras = const SizedBox.shrink();
        break;
      default:
        body =
            'We use this so you can share your location with the people you '
            'choose — even when the app is closed. It\'s end-to-end '
            'encrypted; only your contacts can decrypt it.';
        extras = _PrivacyTip();
    }
    return _StepLayout(
      hero: _PermissionHero(state: _permission),
      title: _permission == _PermissionState.granted
          ? 'You\'re good.'
          : 'Allow location access',
      body: body,
      extras: extras,
    );
  }

  Widget _buildReadyPage() {
    return _StepLayout(
      hero: _ReadyHero(),
      title: 'You\'re set.',
      body: 'Add a friend, and start sharing. Encrypted, only with the '
          'people you choose.',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared step layout
// ─────────────────────────────────────────────────────────────────────

class _StepLayout extends StatelessWidget {
  const _StepLayout({
    required this.hero,
    required this.title,
    required this.body,
    this.extras,
  });

  final Widget hero;
  final String title;
  final String body;
  final Widget? extras;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          hero,
          const SizedBox(height: 28),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.025 * 28,
              color: GridTokens.text,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
              color: GridTokens.text2,
              height: 1.5,
              letterSpacing: -0.005,
            ),
          ),
          if (extras != null) ...[
            const SizedBox(height: 18),
            extras!,
          ],
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Page heroes
// ─────────────────────────────────────────────────────────────────────

class _LogoHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 144,
      height: 144,
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
        width: 92,
        height: 92,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _PermissionHero extends StatelessWidget {
  const _PermissionHero({required this.state});
  final _PermissionState state;

  @override
  Widget build(BuildContext context) {
    final isGranted = state == _PermissionState.granted;
    final isError = state == _PermissionState.deniedForever;
    final accent = isError
        ? GridTokens.amber
        : (isGranted ? GridTokens.mint : GridTokens.mint);
    final iconData = isError
        ? Icons.error_outline_rounded
        : (isGranted
            ? Icons.check_rounded
            : Icons.location_on_rounded);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            accent.withOpacity(0.22),
            accent.withOpacity(0.06),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      alignment: Alignment.center,
      child: state == _PermissionState.requesting
          ? const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: GridTokens.mint,
                strokeWidth: 2.4,
              ),
            )
          : Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.16),
                border: Border.all(color: accent.withOpacity(0.5), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Icon(iconData, size: 34, color: accent),
            ),
    );
  }
}

class _ReadyHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            GridTokens.mint.withOpacity(0.22),
            GridTokens.mint.withOpacity(0.06),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: GridTokens.mint.withOpacity(0.16),
          border: Border.all(
              color: GridTokens.mint.withOpacity(0.5), width: 1.5),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.waving_hand_rounded,
          size: 34,
          color: GridTokens.mint,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Bits
// ─────────────────────────────────────────────────────────────────────

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

class _PrivacyTip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: GridTokens.surface,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined,
              size: 16, color: GridTokens.mint),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 12.5,
                  height: 1.45,
                  color: GridTokens.text2,
                ),
                children: [
                  const TextSpan(
                    text:
                        'Your location is end-to-end encrypted and only visible to the people you pick. ',
                  ),
                  TextSpan(
                    text: 'Read our Privacy Policy',
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
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.active, required this.count});
  final int active;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == active
                  ? GridTokens.mint
                  : GridTokens.hairlineStrong,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
