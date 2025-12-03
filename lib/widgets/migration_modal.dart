import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/services/backwards_compatibility_service.dart';
import 'package:grid_frontend/screens/settings/settings_page.dart';

class MigrationModal extends StatelessWidget {
  const MigrationModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.security,
                size: 64,
                color: Theme.of(context).primaryColor,
              ),
              SizedBox(height: 16),
              Text(
                'Security Upgrade Required',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              Text(
                'We\'ve upgraded our security infrastructure to support the latest Android standards.\n\nTo continue using Grid, please re-login. Your contacts and groups are safely stored on the server.',
                style: TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await BackwardsCompatibilityService.markMigrationComplete();

                    if (context.mounted) {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        '/welcome',
                        (route) => false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    'Re-login Now',
                    style: TextStyle(fontSize: 16),
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
