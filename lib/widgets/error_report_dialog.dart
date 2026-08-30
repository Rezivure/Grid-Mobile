import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:grid_frontend/utilities/error_report.dart';

/// Error dialog for failures the user cannot recover from on their own.
///
/// Passkey signup and login are the cases that matter: there is no SMS
/// fallback any more, so a user who can't create or use a passkey is stuck
/// until a human helps. Rather than showing a dead-end "Something went wrong",
/// this surfaces the raw error and gives them one tap to copy a complete
/// report they can paste into Discord.
///
/// Show it with [showErrorReportDialog].
class ErrorReportDialog extends StatefulWidget {
  /// What the user was attempting, in plain language ("Passkey signup").
  final String action;

  /// The full report text — build it with [buildErrorReport].
  final String report;

  const ErrorReportDialog({
    Key? key,
    required this.action,
    required this.report,
  }) : super(key: key);

  @override
  State<ErrorReportDialog> createState() => _ErrorReportDialogState();
}

class _ErrorReportDialogState extends State<ErrorReportDialog> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.report));
    if (!mounted) return;
    // Confirm in place rather than via a toast: the dialog covers the screen,
    // so a snackbar behind it would be invisible.
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        decoration: BoxDecoration(
          color: colorScheme.background,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(colorScheme),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    errorReportGuidance,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildReportBox(colorScheme),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  _buildCopyButton(colorScheme),
                  const SizedBox(height: 10),
                  _buildDismissButton(colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.05),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        border: Border(
          bottom: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.error_outline, color: Colors.red, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportBox(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      // Long stack traces must not push the buttons off-screen.
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          widget.report,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            fontFamily: 'monospace',
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildCopyButton(ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: TextButton.icon(
          onPressed: _copy,
          style: TextButton.styleFrom(
            backgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: Icon(
            _copied ? Icons.check : Icons.copy,
            size: 18,
            color: colorScheme.onPrimary,
          ),
          label: Text(
            _copied ? 'Copied' : 'Copy error details',
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDismissButton(ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: () => Navigator.of(context).pop(),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          foregroundColor: colorScheme.onSurfaceVariant,
        ),
        child: const Text(
          'Close',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
        ),
      ),
    );
  }
}

/// Shows [ErrorReportDialog] for a failed [action], rendering [error] into a
/// copyable report.
///
/// [username] is included only when the failure happened during signup, where
/// it is the single most useful field for the team to correlate against.
Future<void> showErrorReportDialog(
  BuildContext context, {
  required String action,
  required Object error,
  String? username,
}) {
  final report = buildErrorReport(
    action: action,
    error: error,
    timestamp: DateTime.now(),
    username: username,
    platform: defaultTargetPlatformLabel(),
  );

  return showDialog(
    context: context,
    builder: (_) => ErrorReportDialog(action: action, report: report),
  );
}

/// Short platform label for the report ("android", "ios", …).
String defaultTargetPlatformLabel() =>
    defaultTargetPlatform.name.toLowerCase();
