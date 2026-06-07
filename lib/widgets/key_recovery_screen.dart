import 'package:flutter/material.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';

/// Shown at boot when the encryption key is missing under every known
/// accessibility level. Offers a single recovery action: wipe the local
/// Grid DB and reset. Matrix credentials and sync state are untouched —
/// once the user reopens the app, contacts/locations rebuild from sync.
class KeyRecoveryScreen extends StatefulWidget {
  const KeyRecoveryScreen({
    super.key,
    required this.databaseService,
    required this.onResetComplete,
  });

  final DatabaseService databaseService;
  final VoidCallback onResetComplete;

  @override
  State<KeyRecoveryScreen> createState() => _KeyRecoveryScreenState();
}

class _KeyRecoveryScreenState extends State<KeyRecoveryScreen> {
  bool _resetting = false;
  String? _error;

  Future<void> _handleReset() async {
    setState(() {
      _resetting = true;
      _error = null;
    });
    try {
      await widget.databaseService.resetEncryptionForRecovery();
      widget.onResetComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resetting = false;
        _error = 'Reset failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.lock_reset_outlined,
                  size: 56,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Couldn\'t unlock your data',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'The encryption key for your local data wasn\'t found in '
                  'the keychain. This can happen after some iOS keychain '
                  'changes.\n\nResetting will clear your local Grid data '
                  '(cached contacts, locations) and generate a fresh key. '
                  'Your account and contacts rebuild from sync after reset.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ],
                const SizedBox(height: 32),
                GridButton(
                  label: _resetting ? 'Resetting…' : 'Reset App Data',
                  onPressed: _resetting ? null : _handleReset,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
