import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grid_frontend/widgets/buttons/copy_account_details_button.dart';
import 'package:grid_frontend/widgets/buttons/grid_close_button.dart';
import 'package:grid_frontend/widgets/buttons/open_discord_button.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../styles/grid_colors.dart';
import '../styles/tokens.dart';
import '../utilities/error_report.dart';

Future<void> showAccountDeletionSupportDialog(BuildContext context, {required String details}) async {
  await showDialog(
    context: context,
    builder: (context) {
      return AccountDeletionSupportDialog(details: details);
    },
  );
}

/// Dialog shown when a default-homeserver (passkey) account asks to be deleted.
///
/// There is no option to delete these accounts within the app.
/// Therefore, the only practical option for the app is
/// to provide the user with all the information the team needs,
/// as well as a way to contact the team.
///
/// Copying is the primary action.
/// Opening Discord is secondary.
class AccountDeletionSupportDialog extends StatefulWidget {
  final String details;

  const AccountDeletionSupportDialog({super.key, required this.details});

  @override
  State<AccountDeletionSupportDialog> createState() => _AccountDeletionSupportDialogState();
}

class _AccountDeletionSupportDialogState extends State<AccountDeletionSupportDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    // TODO(Yuki): If all dialogs share the same shadow style, abstract it into a separate widget
    // or if they don't, do it anyway and make all dialogs have the same style

    var borderRadius = BorderRadius.circular(GridTokens.rXl);
    EdgeInsets contentPadding = EdgeInsets.symmetric(horizontal: Gap.bigger.width ?? 0);

    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.gridColors.surface,
          borderRadius: borderRadius,
          border: Border.all(color: context.gridColors.hairline),
          boxShadow: [
            // Because of this shadow, we must use a [Dialog] with a ClipRRect.
            // Other Dialogs (AlertDialog, SimpleDialog) would clip the shadow.
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: Gap.smaller.height ?? 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Title(),
                Gap.bigger,
                Padding(
                  padding: contentPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Passkey accounts can\'t be deleted in the app yet. Copy '
                        'the details below and send them to us on Discord — we\'ll '
                        'remove your account and confirm when it\'s done.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: context.gridColors.text2,
                        ),
                      ),
                      Gap.big,
                      SizedBox(
                        width: double.infinity,
                        child: _DetailBox(
                          details: widget.details,
                        ),
                      )
                    ],
                  ),
                ),
                Gap.normal,
                Padding(
                  padding: contentPadding,
                  child: Column(
                    children: [
                      CopyAccountDetailsButton(
                        copied: _copied,
                        onPressed: _onCopy,
                      ),
                      Gap.small,
                      OpenDiscordButton(
                        onPressed: _openDiscord,
                      ),
                      Gap.smaller,
                      GridCloseButton(
                        onPressed: () => _onClose(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // TODO(Yuki): Add error handling, might throw PlatformException
  Future<void> _onCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.details));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  // TODO(Yuki): centralize all url launches in separate file with error handling
  Future<void> _openDiscord() async {
    final uri = Uri.parse(gridDiscordInvite);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _onClose(BuildContext context) => Navigator.of(context).pop();
}

class _Title extends StatelessWidget {
  const _Title({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.gridColors.dangerSoft,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(GridTokens.rXl),
          topRight: Radius.circular(GridTokens.rXl),
        ),
      ),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.gridColors.danger.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(GridTokens.rMd),
            ),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.support_agent,
                color: context.gridColors.danger,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'We\'ll delete it for you',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.gridColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBox extends StatelessWidget {
  final String details;

  const _DetailBox({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.gridColors.surface2,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: context.gridColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          details,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            fontFamily: 'monospace',
            color: context.gridColors.text2,
          ),
        ),
      ),
    );
  }
}
