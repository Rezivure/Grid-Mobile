import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

class VersionChecker {
  static Future<void> checkVersion(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final versionCheckUrl = dotenv.env['VERSION_CHECK_URL'] ?? '';
      final appStoreUrl = dotenv.env['APP_STORE_URL'] ?? '';
      final playStoreUrl = dotenv.env['PLAY_STORE_URL'] ?? '';

      final response = await http.get(Uri.parse(versionCheckUrl));
      if (response.statusCode != 200) {
        return;
      }

      final versionInfo = json.decode(response.body);
      final minimumVersion = versionInfo['minimum_version'];
      final latestVersion = versionInfo['latest_version'];

      if (isVersionLower(currentVersion, minimumVersion)) {
        _showForceUpdateDialog(context, appStoreUrl, playStoreUrl);
      } else if (isVersionLower(currentVersion, latestVersion)) {
        showOptionalUpdateDialog(context, appStoreUrl, playStoreUrl);
      }
    } catch (e) {
      print('Version check failed: $e');
    }
  }

  static bool isVersionLower(String current, String target) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> targetParts = target.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      if (currentParts[i] < targetParts[i]) return true;
      if (currentParts[i] > targetParts[i]) return false;
    }
    return false;
  }

  static Future<void> launchStoreUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      print('Attempting to launch URL: $url');

      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (!launched) {
          print('URL launch failed for: $url');
        }
      } else {
        print('Cannot launch URL: $url');
        // Fallback to browser URL
        final fallbackUrl = Platform.isIOS
            ? 'https://apps.apple.com'
            : 'https://play.google.com/store';
        await launchUrl(
          Uri.parse(fallbackUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  static void _showForceUpdateDialog(BuildContext context, String appStoreUrl, String playStoreUrl) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            backgroundColor: theme.cardColor,
            title: Text(
              'Update Required',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'A new version of Grid is required to continue. Please update from the app store.',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => launchStoreUrl(Platform.isIOS ? appStoreUrl : playStoreUrl),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.onSurface,
                  foregroundColor: colorScheme.surface,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: Text('Update Now'),
              ),
            ],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: Theme.of(context).brightness == Brightness.dark
                  ? BorderSide(color: theme.colorScheme.surface.withOpacity(0.15))
                  : BorderSide.none,
            ),
          ),
        );
      },
    );
  }

  static void showOptionalUpdateDialog(BuildContext context, String appStoreUrl, String playStoreUrl) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            'Update Available',
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'A new version of Grid is available. Would you like to update now?',
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Later',
                style: TextStyle(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                launchStoreUrl(Platform.isIOS ? appStoreUrl : playStoreUrl);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.onSurface,
                foregroundColor: colorScheme.surface,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text('Update'),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: Theme.of(context).brightness == Brightness.dark
                ? BorderSide(color: theme.colorScheme.surface.withOpacity(0.15))
                : BorderSide.none,
          ),
        );
      },
    );
  }
}