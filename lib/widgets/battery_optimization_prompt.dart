import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:libre_location/libre_location.dart' as libre;
import 'package:shared_preferences/shared_preferences.dart';

class BatteryOptimizationPrompt {
  static const String _seenKey = 'battery_optimization_warning_seen';

  static Future<bool> _shouldShow() async {
    if (!Platform.isAndroid) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey) ?? false) return false;
    // Only show when battery optimization is actually enabled
    try {
      return await libre.LibreLocation.checkBatteryOptimization();
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }

  /// Shows the battery optimisation warning dialog once on Android.
  /// Safe to call on every app start — it is a no-op after the first dismissal
  /// or when battery optimization is already disabled.
  static Future<void> showIfNeeded(BuildContext context) async {
    if (!await _shouldShow()) return;
    if (!context.mounted) return;

    await _markSeen();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BatteryOptimizationDialog(),
    );
  }
}

class _BatteryOptimizationDialog extends StatelessWidget {
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withOpacity(0.12),
                      colorScheme.primary.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.battery_alert_rounded,
                  size: 38,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Disable Battery Optimization',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Android\'s battery optimization may pause Grid in the '
                'background, preventing your location from updating. '
                'Disabling it keeps location sharing reliable when the '
                'app is not in the foreground.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    try {
                      await libre.LibreLocation
                          .requestBatteryOptimizationExemption();
                    } catch (e) {
                      debugPrint('Battery exemption request failed: $e');
                    }
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Fix It Now',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Not Now',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
