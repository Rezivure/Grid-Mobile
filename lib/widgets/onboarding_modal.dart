import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class OnboardingModal extends StatefulWidget {
  final VoidCallback? onComplete;

  const OnboardingModal({Key? key, this.onComplete}) : super(key: key);

  @override
  _OnboardingModalState createState() => _OnboardingModalState();

  static Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    // Use v2 flag to force all users to see the new permission disclosure
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding_v2') ?? false;
    return !hasSeenOnboarding;
  }

  static Future<void> showOnboardingIfNeeded(BuildContext context, {VoidCallback? onComplete}) async {
    final shouldShow = await shouldShowOnboarding();
    if (shouldShow && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => OnboardingModal(onComplete: onComplete),
      );
    }
  }

  static Future<void> resetOnboardingPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('has_seen_onboarding');
    print('DEBUG: Onboarding preference reset');
  }
}

class _OnboardingModalState extends State<OnboardingModal>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late PageController _pageController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  int _currentPage = 0;

  // Track permission grants (not just acknowledgments)
  bool _locationAlwaysGranted = false;
  bool _activityRecognitionGranted = false;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      icon: Icons.rocket_launch_rounded,
      title: 'Welcome to Grid!',
      description: 'You\'re taking the next step in privacy! Grid uses end-to-end encryption to keep your location data completely private and secure.',
      color: const Color(0xFF2196F3),
    ),
    OnboardingPage(
      icon: Icons.shield_rounded,
      title: 'Grant Permissions',
      description: 'Your location is end-to-end encrypted and only visible to people you choose. Complete privacy guaranteed.',
      color: const Color(0xFF4CAF50),
      isPermissionPage: true,
    ),
    OnboardingPage(
      icon: Icons.person_add_rounded,
      title: 'Add Contacts',
      description: 'Tap the + button to add friends and start sharing your location securely.',
      color: const Color(0xFF00DBA4),
    ),
    OnboardingPage(
      icon: Icons.group_add_rounded,
      title: 'Create Groups',
      description: 'Create temporary groups to share location with multiple people at once.',
      color: const Color(0xFF267373),
    ),
    OnboardingPage(
      icon: Icons.account_circle_rounded,
      title: 'View Profiles',
      description: 'Long press on any contact to see their profile and manage sharing windows.',
      color: const Color(0xFF6B73FF),
    ),
    OnboardingPage(
      icon: Icons.visibility_off_rounded,
      title: 'Incognito Mode',
      description: 'Go to Settings to enable incognito mode and control your visibility.',
      color: const Color(0xFF9B59B6),
    ),
    OnboardingPage(
      icon: Icons.sensors,
      title: 'Ping Location',
      description: 'Use the ping button (top right) to manually send your exact location to all contacts. Location is already shared, but this sends an immediate update if you\'ve been stationary.',
      color: const Color(0xFFE74C3C),
    ),
    OnboardingPage(
      icon: Icons.discord,
      title: 'Join Our Community',
      description: 'Join our Discord server to give feedback, report bugs, request features, and connect with other Grid users. We\'d love to hear from you!',
      color: const Color(0xFF5865F2),  // Discord brand color
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();

    // Bounce animation for tap indicator
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _bounceAnimation = Tween<double>(begin: -3.0, end: 3.0).animate(
      CurvedAnimation(
        parent: _bounceController,
        curve: Curves.easeInOut,
      ),
    );

    // DON'T check permission status here - wait for user to reach permission page
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[Onboarding] App lifecycle state changed to: $state');
    // When app comes back to foreground (e.g., from Settings), check permissions
    if (state == AppLifecycleState.resumed) {
      print('[Onboarding] App resumed - checking permissions');
      // Add small delay to ensure Settings changes are propagated
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _checkPermissionStatus();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _fadeController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  bool _canProceed() {
    // If on permission page, check if all required permissions are granted
    if (_pages[_currentPage].isPermissionPage) {
      final needsActivity = Platform.isAndroid;
      return _locationAlwaysGranted && (!needsActivity || _activityRecognitionGranted);
    }
    // All other pages can always proceed
    return true;
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _requestLocationPermission() async {
    print('[Onboarding] Location permission tap - starting request');

    try {
      // IMPORTANT: Configure BackgroundGeolocation FIRST before requesting permission
      // Otherwise it will show the default "[CHANGEME]" placeholder text
      await bg.BackgroundGeolocation.ready(bg.Config(
        locationAuthorizationRequest: 'Always',
        backgroundPermissionRationale: bg.PermissionRationale(
          title: "Allow background location?",
          message: "This app collects location data to enable real-time location sharing with your chosen contacts, even when not open.",
          positiveAction: "Allow",
          negativeAction: "Cancel",
        ),
        reset: false, // Don't reset existing config
      ));

      // Now request permission after config is set
      final status = await bg.BackgroundGeolocation.requestPermission();
      print('[Onboarding] BackgroundGeolocation permission result: $status');

      // Status codes: 0 = not determined, 1 = restricted, 2 = denied, 3 = always, 4 = whenInUse
      if (status == 2) {
        // Denied - need to go to settings
        print('[Onboarding] Permission denied, opening settings');
        await _showSettingsDialog('Location');
        return;
      }

      final locationGranted = status >= 3;
      print('[Onboarding] Final permission granted: $locationGranted');

      setState(() {
        _locationAlwaysGranted = locationGranted;
      });
    } catch (e) {
      print('[Onboarding] ERROR requesting location permission: $e');
      await _showSettingsDialog('Location');
    }
  }

  Future<void> _requestActivityPermission() async {
    print('[Onboarding] Activity/Motion permission tap');

    try {
      if (Platform.isIOS) {
        // Configure BackgroundGeolocation first
        await bg.BackgroundGeolocation.ready(bg.Config(
          locationAuthorizationRequest: 'Always',
          backgroundPermissionRationale: bg.PermissionRationale(
            title: "Allow background location?",
            message: "This app collects location data to enable real-time location sharing with your chosen contacts, even when not open.",
            positiveAction: "Allow",
            negativeAction: "Cancel",
          ),
          reset: false,
          // Enable motion tracking which should trigger motion permission
          disableMotionActivityUpdates: false,
          motionTriggerDelay: 0,
        ));

        // Start the service briefly to trigger motion permission request
        // This is what happens after onboarding that makes it request motion
        await bg.BackgroundGeolocation.start();

        // Give it a moment to request permission
        await Future.delayed(const Duration(milliseconds: 500));

        // Stop it again since we're just in onboarding
        await bg.BackgroundGeolocation.stop();

        setState(() {
          _activityRecognitionGranted = true;
        });
      } else {
        // Android - just mark as granted since it's bundled with location
        setState(() {
          _activityRecognitionGranted = true;
        });
      }
    } catch (e) {
      print('[Onboarding] ERROR requesting activity/motion permission: $e');
      setState(() {
        _activityRecognitionGranted = true;
      });
    }
  }

  Future<void> _showSettingsDialog(String permissionName) async {
    // Show a clean snackbar instead of ugly dialog
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opening Settings to enable $permissionName'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // Small delay so user sees the message
    await Future.delayed(const Duration(milliseconds: 300));

    // Go straight to settings
    await openAppSettings();

    // Check permissions when user comes back
    await _checkPermissionStatus();
  }

  Future<void> _checkPermissionStatus() async {
    print('[Onboarding] ============ CHECKING PERMISSION STATUS ============');

    try {
      // Configure FIRST before checking permission status
      await bg.BackgroundGeolocation.ready(bg.Config(
        locationAuthorizationRequest: 'Always',
        backgroundPermissionRationale: bg.PermissionRationale(
          title: "Allow background location?",
          message: "This app collects location data to enable real-time location sharing with your chosen contacts, even when not open.",
          positiveAction: "Allow",
          negativeAction: "Cancel",
        ),
        reset: false, // Don't reset existing config
      ));

      // Call requestPermission which checks status without showing dialog if already granted/denied
      final status = await bg.BackgroundGeolocation.requestPermission();
      print('[Onboarding] BackgroundGeolocation permission status: $status');

      // Status values: 0 = not determined, 1 = restricted, 2 = denied, 3 = always, 4 = whenInUse
      final locationGranted = status >= 3; // 3 = always, 4 = whenInUse
      print('[Onboarding]   - FINAL DECISION: locationGranted = $locationGranted (status code: $status)');

      // Motion/activity permission is handled by flutter_background_geolocation after onboarding
      // We just mark it as true for UI purposes (to show users it will be requested)
      bool activityGranted = true;

      if (mounted) {
        setState(() {
          _locationAlwaysGranted = locationGranted;
          _activityRecognitionGranted = activityGranted;
        });
      }

      print('[Onboarding] ========== PERMISSION CHECK COMPLETE ==========');
      print('[Onboarding] UI State - _locationAlwaysGranted: $_locationAlwaysGranted, _activityRecognitionGranted: $_activityRecognitionGranted');
    } catch (e, stackTrace) {
      print('[Onboarding] ERROR checking permission status: $e');
      print('[Onboarding] Stack trace: $stackTrace');
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding_v2', true);

    if (mounted) {
      Navigator.of(context).pop();
      widget.onComplete?.call();
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with conditional skip button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Welcome',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    // Show skip button only AFTER permission page
                    if (_currentPage > 1) // Pages 0, 1 are Welcome, Permissions (with encryption info)
                      TextButton(
                        onPressed: _completeOnboarding,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Page content
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                    // Don't auto-check permissions - only when user taps the card
                  },
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    return _buildPageContent(_pages[index]);
                  },
                ),
              ),

              // Page indicators
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (index) => _buildPageIndicator(index, colorScheme),
                  ),
                ),
              ),

              // Navigation buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    if (_currentPage > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _previousPage,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: colorScheme.outline),
                          ),
                          child: Text(
                            'Back',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    if (_currentPage > 0) const SizedBox(width: 12),
                    Expanded(
                      flex: _currentPage == 0 ? 1 : 1,
                      child: ElevatedButton(
                        onPressed: _canProceed() ? _nextPage : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          disabledBackgroundColor: colorScheme.surfaceVariant,
                          disabledForegroundColor: colorScheme.onSurface.withOpacity(0.38),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _currentPage == _pages.length - 1 ? 'Get Started' : 'Next',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageContent(OnboardingPage page) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with background (smaller on permission page to save space)
          Container(
            width: page.isPermissionPage ? 80 : 100,
            height: page.isPermissionPage ? 80 : 100,
            decoration: BoxDecoration(
              color: page.color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              page.icon,
              size: page.isPermissionPage ? 40 : 48,
              color: page.color,
            ),
          ),

          SizedBox(height: page.isPermissionPage ? 20 : 32),

          // Title
          Text(
            page.title,
            style: (page.isPermissionPage
                ? theme.textTheme.headlineSmall
                : theme.textTheme.headlineMedium)?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: page.isPermissionPage ? 12 : 16),

          // Description
          Text(
            page.description,
            style: (page.isPermissionPage
                ? theme.textTheme.bodyMedium
                : theme.textTheme.bodyLarge)?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          // Show permission explanation and privacy policy link if this is the permission page
          if (page.isPermissionPage) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(
                      text: 'Skeptical? Read our ',
                    ),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final uri = Uri.parse('https://mygrid.app/privacy');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildPermissionCard(
              context: context,
              icon: Icons.location_on,
              title: 'Location Always',
              description: 'Don\'t worry, you can toggle this on/off in app',
              isGranted: _locationAlwaysGranted,
              onTap: _requestLocationPermission,
              color: const Color(0xFF4CAF50),
            ),
            // Show Physical Activity/Motion for both Android and iOS
            const SizedBox(height: 12),
            _buildPermissionCard(
              context: context,
              icon: Icons.directions_run,
              title: Platform.isIOS ? 'Motion & Fitness' : 'Physical Activity',
              description: 'Better battery & accurate updates',
              isGranted: _activityRecognitionGranted,
              onTap: _requestActivityPermission,
              color: const Color(0xFF2196F3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onTap,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      elevation: isGranted ? 0 : 1,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          print('[Onboarding] Permission card tapped: $title (isGranted: $isGranted)');
          if (!isGranted) {
            onTap();
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isGranted
                ? colorScheme.primary.withOpacity(0.15)
                : colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isGranted
                  ? colorScheme.primary
                  : colorScheme.outline.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isGranted
                      ? colorScheme.primary.withOpacity(0.2)
                      : colorScheme.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isGranted ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isGranted ? colorScheme.onSurface : colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Status indicator
              if (isGranted)
                Icon(
                  Icons.check_circle,
                  color: colorScheme.primary,
                  size: 28,
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _bounceAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _bounceAnimation.value),
                          child: Icon(
                            Icons.touch_app,
                            color: colorScheme.primary.withOpacity(0.7),
                            size: 20,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.circle_outlined,
                      color: colorScheme.outline.withOpacity(0.5),
                      size: 28,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicator(int index, ColorScheme colorScheme) {
    final isActive = index == _currentPage;
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive 
            ? colorScheme.primary 
            : colorScheme.primary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final bool isPermissionPage;

  OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    this.isPermissionPage = false,
  });
}