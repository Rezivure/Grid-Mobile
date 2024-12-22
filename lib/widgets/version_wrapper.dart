import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/widgets/version_checker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class VersionWrapper extends StatefulWidget {
  final Widget child;
  final Client client;

  const VersionWrapper({
    Key? key,
    required this.child,
    required this.client,
  }) : super(key: key);

  @override
  State<VersionWrapper> createState() => _VersionWrapperState();
}

class _VersionWrapperState extends State<VersionWrapper> {
  bool _needsCriticalUpdate = false;
  bool _checkComplete = false;

  @override
  void initState() {
    super.initState();
    _checkVersion();
  }

  Future<void> _checkVersion() async {
    print('Checking version...');
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      print('Current version: $currentVersion');

      final versionCheckUrl = dotenv.env['VERSION_CHECK_URL'] ?? '';
      final response = await http.get(Uri.parse(versionCheckUrl));

      if (response.statusCode == 200) {
        final versionInfo = json.decode(response.body);
        final minimumVersion = versionInfo['minimum_version'];
        final latestVersion = versionInfo['latest_version'];
        print('Minimum version: $minimumVersion');
        print('Latest version: $latestVersion');

        bool isCritical = VersionChecker.isVersionLower(currentVersion, minimumVersion);
        bool hasOptionalUpdate = VersionChecker.isVersionLower(currentVersion, latestVersion);

        print('Needs critical update: $isCritical');
        print('Has optional update: $hasOptionalUpdate');

        if (mounted) {
          setState(() {
            _needsCriticalUpdate = isCritical;
            _checkComplete = true;
          });

          if (isCritical) {
            VersionChecker.checkVersion(context);
          } else if (hasOptionalUpdate) {
            // Show optional update dialog if there's a newer version but not critical
            VersionChecker.showOptionalUpdateDialog(
                context,
                dotenv.env['APP_STORE_URL'] ?? '',
                dotenv.env['PLAY_STORE_URL'] ?? ''
            );
          }
        }
      }
    } catch (e) {
      print('Version check error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _checkComplete = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkComplete) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          body: Center(
            child: Image.asset(
              'assets/logos/png-file-2.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    }

    if (_needsCriticalUpdate) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          body: Center(
            child: Image.asset(
              'assets/logos/png-file-2.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}