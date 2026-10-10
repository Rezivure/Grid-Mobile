import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';

Future<bool> showDeleteIconDialog(BuildContext context) async {
  bool? delete = await showDialog(
    context: context,
    builder: (context) {
      return DeleteIconDialog();
    },
  );

  return delete ?? false;
}

class DeleteIconDialog extends StatelessWidget {
  const DeleteIconDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO(Yuki): replace with generic grid dialog once all relevant PRs are merged

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.9,
        ),
        decoration: BoxDecoration(
          color: context.gridColors.surface,
          borderRadius: BorderRadius.circular(GridTokens.rXl),
          border: Border.all(color: context.gridColors.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.gridColors.danger.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(GridTokens.rMd),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.delete_outline,
                      color: context.gridColors.danger,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delete icon',
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
                          "This can't be undone.",
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Text(
                'This icon will be permanently removed from the map.',
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: context.gridColors.text2,
                  height: 1.45,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: GridButton(
                      label: 'Cancel',
                      style: GridButtonStyle.secondary,
                      onPressed: () => _onCancel(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GridButton(
                      label: 'Delete',
                      style: GridButtonStyle.danger,
                      onPressed: () => _onDelete(context),
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

  void _onDelete(BuildContext context) => Navigator.of(context).pop(true);
  void _onCancel(BuildContext context) => Navigator.of(context).pop(false);
}
