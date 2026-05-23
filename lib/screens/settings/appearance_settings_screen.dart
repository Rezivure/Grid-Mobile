import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/services/theme_controller.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gridColors.bg,
      appBar: AppBar(
        backgroundColor: context.gridColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Appearance',
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: context.gridColors.text,
            letterSpacing: -0.01,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.gridColors.text,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            AnimatedBuilder(
              animation: ThemeController.instance,
              builder: (context, _) => Container(
                decoration: BoxDecoration(
                  color: context.gridColors.surface,
                  borderRadius: BorderRadius.circular(GridTokens.rLg),
                  border: Border.all(color: context.gridColors.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ThemeModeRow(
                      icon: Icons.brightness_auto_outlined,
                      title: 'System',
                      selected:
                          ThemeController.instance.mode == ThemeMode.system,
                      onTap: () => ThemeController.instance
                          .setMode(ThemeMode.system),
                    ),
                    _divider(context),
                    ThemeModeRow(
                      icon: Icons.light_mode_outlined,
                      title: 'Light',
                      selected:
                          ThemeController.instance.mode == ThemeMode.light,
                      onTap: () => ThemeController.instance
                          .setMode(ThemeMode.light),
                    ),
                    _divider(context),
                    ThemeModeRow(
                      icon: Icons.dark_mode_outlined,
                      title: 'Dark',
                      selected:
                          ThemeController.instance.mode == ThemeMode.dark,
                      onTap: () => ThemeController.instance
                          .setMode(ThemeMode.dark),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 56),
        child: Divider(
          height: 1,
          thickness: 1,
          color: context.gridColors.hairline,
        ),
      );
}

class ThemeModeRow extends StatelessWidget {
  const ThemeModeRow({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        selected ? context.gridColors.mint : context.gridColors.text2;
    final Color titleColor = context.gridColors.text;

    return Material(
      color: selected ? context.gridColors.mintFaint : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.getFont(
                    'Geist',
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.01,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: context.gridColors.mint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
