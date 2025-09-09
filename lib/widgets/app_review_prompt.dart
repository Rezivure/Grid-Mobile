import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'dart:async';

class AppReviewPrompt extends StatefulWidget {
  const AppReviewPrompt({Key? key}) : super(key: key);

  @override
  State<AppReviewPrompt> createState() => _AppReviewPromptState();
}

class _AppReviewPromptState extends State<AppReviewPrompt> {
  int _selectedRating = 0;
  
  // App Store URLs
  static const String _iosAppId = '6736839927'; // Grid App Store ID (from actual App Store URL)
  static const String _androidPackageName = 'app.mygrid.grid'; // Grid package name
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.4 : 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Icon with gradient background
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withOpacity(0.1),
                      colorScheme.primary.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.favorite_rounded,
                  size: 40,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              
              Text(
                'Enjoying Grid?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your feedback helps us make Grid better for everyone',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              
              // Star Rating with animation
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  final starNumber = index + 1;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRating = starNumber;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          _selectedRating >= starNumber
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          key: ValueKey('star_$starNumber${_selectedRating >= starNumber}'),
                          size: _selectedRating >= starNumber ? 42 : 38,
                          color: _selectedRating >= starNumber
                              ? const Color(0xFFFFB800)
                              : colorScheme.outline.withOpacity(0.5),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              
              // Rating text
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: _selectedRating > 0 ? 32 : 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _selectedRating > 0 ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _getRatingText(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _getRatingColor(colorScheme),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Action Buttons with better styling
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        _handleNotNow();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Maybe Later',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      child: FilledButton(
                        onPressed: _selectedRating > 0 ? () {
                          _handleRatingSubmit();
                        } : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: _selectedRating > 0 
                              ? colorScheme.primary 
                              : colorScheme.surfaceVariant,
                          foregroundColor: _selectedRating > 0
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: _selectedRating > 0 ? 2 : 0,
                        ),
                        child: Text(
                          'Submit',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
  
  String _getRatingText() {
    switch (_selectedRating) {
      case 1:
        return 'We\'ll do better 😔';
      case 2:
        return 'Thanks for the feedback 🙏';
      case 3:
        return 'We appreciate your honesty 👍';
      case 4:
        return 'Glad you like it! 😊';
      case 5:
        return 'You\'re amazing! 🎉';
      default:
        return '';
    }
  }
  
  Color _getRatingColor(ColorScheme colorScheme) {
    if (_selectedRating >= 4) {
      return Colors.green;
    } else if (_selectedRating == 3) {
      return Colors.orange;
    } else {
      return colorScheme.error;
    }
  }
  
  Future<void> _handleNotNow() async {
    // Save that we prompted but user declined
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('review_prompt_last_shown', DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt('review_prompt_count', (prefs.getInt('review_prompt_count') ?? 0) + 1);
    
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
  
  Future<void> _handleRatingSubmit() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (_selectedRating >= 4) {
      // High rating - redirect to app store
      await prefs.setBool('has_reviewed', true);
      await prefs.setInt('user_rating', _selectedRating);
      
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Launch app store review
      _launchAppStoreReview();
    } else {
      // Low rating - show feedback option
      if (mounted) {
        Navigator.of(context).pop();
        _showFeedbackDialog();
      }
    }
  }
  
  void _showFeedbackDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary.withOpacity(0.1),
                          colorScheme.primary.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 40,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Help Us Improve',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We appreciate your honesty! Would you like to share what we could do better?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            // Save that they gave low rating but declined feedback
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('has_reviewed', true);
                            await prefs.setInt('user_rating', _selectedRating);
                            Navigator.of(context).pop();
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'No Thanks',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            // Save rating and launch feedback
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('has_reviewed', true);
                            await prefs.setInt('user_rating', _selectedRating);
                            
                            Navigator.of(context).pop();
                            _launchFeedbackForm();
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: colorScheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Send Feedback',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  Future<void> _launchAppStoreReview() async {
    try {
      String url;
      
      if (Platform.isIOS) {
        // iOS App Store review URL - try native first, then web fallback
        // Native iOS URL scheme
        url = 'itms-apps://itunes.apple.com/app/id$_iosAppId?action=write-review';
        
        final nativeUri = Uri.parse(url);
        if (await canLaunchUrl(nativeUri)) {
          await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
          return;
        }
        
        // Fallback to web URL if native doesn't work (e.g., simulator)
        url = 'https://apps.apple.com/app/id$_iosAppId';
      } else if (Platform.isAndroid) {
        // Google Play Store review URL
        url = 'market://details?id=$_androidPackageName';
        
        final nativeUri = Uri.parse(url);
        if (await canLaunchUrl(nativeUri)) {
          await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
          return;
        }
        
        // Fallback to web URL
        url = 'https://play.google.com/store/apps/details?id=$_androidPackageName';
      } else {
        // Fallback to feedback form for other platforms
        _launchFeedbackForm();
        return;
      }
      
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // If we're in simulator/emulator, show a message
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Thank you! App Store review will open on a real device.'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('Error launching app store: $e');
      // Fallback to feedback form if any error occurs
      _launchFeedbackForm();
    }
  }
  
  Future<void> _launchFeedbackForm() async {
    final uri = Uri.parse('https://mygrid.app/feedback');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
    }
  }
}

class AppReviewManager {
  static const String _hasReviewedKey = 'has_reviewed';
  static const String _firstLaunchKey = 'first_launch_time';
  static const String _sessionCountKey = 'session_count';
  static const String _lastPromptKey = 'review_prompt_last_shown';
  static const String _promptCountKey = 'review_prompt_count';
  static const String _totalUsageMinutesKey = 'total_usage_minutes';
  static const String _lastActiveTimeKey = 'last_active_time';
  
  // Configuration
  static const int _minSessionsBeforePrompt = 3; // At least 3 app sessions
  static const int _minDaysBeforePrompt = 2; // At least 2 days since install
  static const int _minTotalUsageMinutes = 30; // At least 30 minutes total usage (not consecutive)
  static const int _daysBetweenPrompts = 30; // If declined, wait 30 days before asking again
  static const int _maxPromptCount = 3; // Maximum times to prompt if declined
  
  static DateTime? _sessionStartTime;
  static Timer? _usageTimer;
  
  static void startSession() {
    _sessionStartTime = DateTime.now();
    _incrementSessionCount();
    _startUsageTracking();
  }
  
  static void _startUsageTracking() {
    // Cancel any existing timer
    _usageTimer?.cancel();
    
    // Update usage time every minute while app is active
    _usageTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateUsageTime();
    });
    
    // Also update immediately
    _updateUsageTime();
  }
  
  static Future<void> _updateUsageTime() async {
    final prefs = await SharedPreferences.getInstance();
    final currentMinutes = prefs.getInt(_totalUsageMinutesKey) ?? 0;
    await prefs.setInt(_totalUsageMinutesKey, currentMinutes + 1);
    await prefs.setInt(_lastActiveTimeKey, DateTime.now().millisecondsSinceEpoch);
  }
  
  static void stopSession() {
    _usageTimer?.cancel();
    _usageTimer = null;
  }
  
  static Future<void> _incrementSessionCount() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Record first launch if not set
    if (!prefs.containsKey(_firstLaunchKey)) {
      await prefs.setInt(_firstLaunchKey, DateTime.now().millisecondsSinceEpoch);
    }
    
    // Increment session count
    final currentCount = prefs.getInt(_sessionCountKey) ?? 0;
    await prefs.setInt(_sessionCountKey, currentCount + 1);
  }
  
  static Future<bool> shouldShowReviewPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if already reviewed
    if (prefs.getBool(_hasReviewedKey) ?? false) {
      return false;
    }
    
    // Check prompt count
    final promptCount = prefs.getInt(_promptCountKey) ?? 0;
    if (promptCount >= _maxPromptCount) {
      return false;
    }
    
    // Check session count
    final sessionCount = prefs.getInt(_sessionCountKey) ?? 0;
    if (sessionCount < _minSessionsBeforePrompt) {
      return false;
    }
    
    // Check days since install
    final firstLaunch = prefs.getInt(_firstLaunchKey);
    if (firstLaunch != null) {
      final daysSinceInstall = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(firstLaunch))
          .inDays;
      if (daysSinceInstall < _minDaysBeforePrompt) {
        return false;
      }
    }
    
    // Check total cumulative usage time
    final totalUsageMinutes = prefs.getInt(_totalUsageMinutesKey) ?? 0;
    if (totalUsageMinutes < _minTotalUsageMinutes) {
      return false;
    }
    
    // Check days since last prompt
    final lastPrompt = prefs.getInt(_lastPromptKey);
    if (lastPrompt != null) {
      final daysSinceLastPrompt = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastPrompt))
          .inDays;
      if (daysSinceLastPrompt < _daysBetweenPrompts) {
        return false;
      }
    }
    
    return true;
  }
  
  static Future<bool> showReviewPromptIfNeeded(BuildContext context) async {
    if (await shouldShowReviewPrompt()) {
      // Save that we're showing the prompt
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastPromptKey, DateTime.now().millisecondsSinceEpoch);
      
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => const AppReviewPrompt(),
        );
        return true;
      }
    }
    return false;
  }
}