import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_segmented.dart';

/// Read-only view of the local Matrix device's identity material.
///
/// Replaces the legacy `_showInfoModal('Device ID' / 'Identity Key', ...)`
/// dialog pair from settings_page.dart with a single sub-page styled to
/// match `PasskeyManagementScreen`.
class EncryptionKeysScreen extends StatelessWidget {
  const EncryptionKeysScreen({
    super.key,
    required this.deviceId,
    required this.identityKey,
  });

  /// May be null while the values are still loading on the settings page.
  final String? deviceId;
  final String? identityKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gridColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Encryption keys',
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: context.gridColors.text,
            letterSpacing: -0.01,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.gridColors.text),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _buildInfoCard(context),
            const GridSectionHeader(text: 'YOUR DEVICE'),
            Container(
              decoration: BoxDecoration(
                color: context.gridColors.surface,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
                border: Border.all(color: context.gridColors.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _KeyRow(
                    icon: Icons.fingerprint_rounded,
                    label: 'Device ID',
                    value: deviceId,
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: context.gridColors.hairline,
                    indent: 56,
                  ),
                  _KeyRow(
                    icon: Icons.key_rounded,
                    label: 'Identity Key',
                    value: identityKey,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.gridColors.mintFaint,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: context.gridColors.mintSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            color: context.gridColors.mint,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Your device's keys identify it to the network. "
              'Treat these like passwords — never share them.',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                color: context.gridColors.text2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String? value;

  bool get _isLoading => value == null || value!.isEmpty;

  Future<void> _copy(BuildContext context) async {
    if (_isLoading) return;
    await Clipboard.setData(ClipboardData(text: value!));
    if (!context.mounted) return;
    InAppNotifier.instance.show(
      title: '$label copied',
      variant: InAppNotificationVariant.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _copy(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: context.gridColors.mintFaint,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: context.gridColors.mint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.getFont(
                        'Geist',
                        color: context.gridColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.01,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_isLoading)
                      GridMono(
                        'LOADING…',
                        size: 11,
                        color: context.gridColors.text3,
                        letterSpacing: 0.1,
                      )
                    else
                      SelectableText(
                        value!,
                        style: GoogleFonts.getFont(
                          'Geist Mono',
                          color: context.gridColors.text2,
                          fontSize: 12.5,
                          height: 1.35,
                          letterSpacing: 0.02,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.copy_rounded,
                size: 16,
                color: _isLoading ? context.gridColors.text4 : context.gridColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
