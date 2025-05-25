import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingModal extends StatefulWidget {
  final VoidCallback? onComplete;

  const OnboardingModal({Key? key, this.onComplete}) : super(key: key);

  @override
  _OnboardingModalState createState() => _OnboardingModalState();

  static Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
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
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  int _currentPage = 0;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      icon: Icons.rocket_launch_rounded,
      title: 'Congrats!',
      description: 'You\'re taking the next step in privacy! Here are some tips to help you use Grid effectively and securely.',
      color: const Color(0xFF2196F3),
    ),
    OnboardingPage(
      icon: Icons.shield_rounded,
      title: 'End-to-End Encrypted',
      description: 'Your location data is fully encrypted and only visible to people you choose to share with. Complete privacy guaranteed.',
      color: const Color(0xFF4CAF50),
    ),
    OnboardingPage(
      icon: Icons.location_on_rounded,
      title: 'Location Permissions',
      description: 'Please enable location permissions and set to "Always Allow" in your device settings for Grid to work properly.',
      color: const Color(0xFFFF9800),
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
  ];

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
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
    await prefs.setBool('has_seen_onboarding', true);
    
    if (mounted) {
      Navigator.of(context).pop();
      widget.onComplete?.call();
    }
  }

  void _skipOnboarding() {
    _completeOnboarding();
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
              // Header with skip button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tips',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    TextButton(
                      onPressed: _skipOnboarding,
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
                        onPressed: _nextPage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with background
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: page.color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              page.icon,
              size: 48,
              color: page.color,
            ),
          ),

          const SizedBox(height: 32),

          // Title
          Text(
            page.title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Description
          Text(
            page.description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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

  OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}