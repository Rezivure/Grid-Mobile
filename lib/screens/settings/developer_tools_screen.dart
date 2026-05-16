import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../styles/tokens.dart';
import '../../widgets/grid/grid_segmented.dart';
import 'developer_settings_screen.dart';

/// Hidden developer tools page, reached by tapping the version footer in
/// Settings 5 times in quick succession. Mirrors the dark-mode Geist styling
/// used by the rest of the settings tree (see [SettingsPage]) so it feels
/// like a normal screen rather than a debug pane.
class DeveloperToolsScreen extends StatelessWidget {
  const DeveloperToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GridTokens.bg,
      appBar: AppBar(
        backgroundColor: GridTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: GridTokens.text,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Developer tools',
          style: GoogleFonts.getFont(
            'Geist',
            color: GridTokens.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.015,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            const GridSectionHeader(text: 'Diagnostics'),
            Container(
              decoration: BoxDecoration(
                color: GridTokens.surface,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
                border: Border.all(color: GridTokens.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _DevMenuOption(
                    icon: Icons.bug_report_outlined,
                    title: 'Location Debugging',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeveloperSettingsScreen(),
                        ),
                      );
                    },
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

/// Local copy of the settings-page row pattern. Kept private to this file so
/// the dev-tools screen stays self-contained and we don't widen the public
/// API of [SettingsPage].
class _DevMenuOption extends StatelessWidget {
  const _DevMenuOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: GridTokens.text2),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.getFont(
                    'Geist',
                    color: GridTokens.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.01,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: GridTokens.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
