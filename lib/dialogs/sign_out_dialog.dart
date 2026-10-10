import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/buttons/cancel_button.dart';
import 'package:grid_frontend/widgets/buttons/sign_out_button.dart';
import 'package:grid_frontend/widgets/layout/bullet_point.dart';
import 'package:grid_frontend/widgets/layout/bullet_point_menu.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';

Future<bool> showSignOutDialog(BuildContext context) async {
  bool? signOut = await showDialog(
    context: context,
    builder: (context) {
      return SignOutDialog();
    },
  );

  return signOut ?? false;
}

class SignOutDialog extends StatelessWidget {
  const SignOutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO(Yuki): This is the second dialog with the same design,
    //  abstract it into another widget once the necessary PRs regarding the SettingPage are merged

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
              children: [
                const _Title(),
                Gap.big,
                // Body
                Padding(
                  padding: contentPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Are you sure you want to sign out?',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: context.gridColors.text2,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      BulletPointMenu(children: [
                        BulletPoint(
                          icon: Icon(Icons.location_off),
                          child: Text('Location sharing will be stopped'),
                        ),
                        BulletPoint(
                          icon: Icon(Icons.sync_disabled),
                          child: Text("You'll need to sign in again to access your account"),
                        ),
                      ]),
                    ],
                  ),
                ),
                Gap.big,
                // Actions
                Padding(
                  padding: contentPadding,
                  child: Row(
                    children: [
                      Expanded(
                        child: CancelButton(
                          onPressed: () => _onCancel(context),
                        ),
                      ),
                      Gap.normal,
                      Expanded(
                        child: SignOutButton(
                          onPressed: () => _onSignOut(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Gap.normal,
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onCancel(BuildContext context) => Navigator.pop(context, false);
  void _onSignOut(BuildContext context) =>  Navigator.pop(context, true);
}

class _Title extends StatelessWidget {
  const _Title({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.gridColors.mintFaint,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(GridTokens.rXl),
          topRight: Radius.circular(GridTokens.rXl),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.gridColors.mintSoft,
                borderRadius: BorderRadius.circular(GridTokens.rMd),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.logout,
                color: context.gridColors.mint,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sign out',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.015,
                      color: context.gridColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You can always sign back in',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: context.gridColors.text2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
