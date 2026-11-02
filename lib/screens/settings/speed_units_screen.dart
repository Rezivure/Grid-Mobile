import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/screens/settings/appearance_settings_screen.dart';
import 'package:grid_frontend/services/units_controller.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';

class SpeedUnitsScreen extends StatelessWidget {
  const SpeedUnitsScreen({super.key});

  static const _titles = {
    SpeedUnit.mph: 'Miles per hour (mph)',
    SpeedUnit.kmh: 'Kilometers per hour (km/h)',
    SpeedUnit.mps: 'Meters per second (m/s)',
  };

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
          'Speed units',
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
              animation: UnitsController.instance,
              builder: (context, _) => Container(
                decoration: BoxDecoration(
                  color: context.gridColors.surface,
                  borderRadius: BorderRadius.circular(GridTokens.rLg),
                  border: Border.all(color: context.gridColors.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final unit in SpeedUnit.values) ...[
                      if (unit != SpeedUnit.values.first) _divider(context),
                      ThemeModeRow(
                        icon: Icons.speed_rounded,
                        title: _titles[unit]!,
                        selected: UnitsController.instance.speedUnit == unit,
                        onTap: () =>
                            UnitsController.instance.setSpeedUnit(unit),
                      ),
                    ],
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
