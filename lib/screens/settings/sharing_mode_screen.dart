import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/services/location/location_dispatch.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';

class SharingModeScreen extends StatefulWidget {
  const SharingModeScreen({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final SharingMode initial;
  final ValueChanged<SharingMode> onChanged;

  @override
  State<SharingModeScreen> createState() => _SharingModeScreenState();
}

class _SharingModeScreenState extends State<SharingModeScreen> {
  late SharingMode _selected = widget.initial;

  static const _modes = <_ModeInfo>[
    _ModeInfo(
      mode: SharingMode.light,
      label: 'Light',
      icon: Icons.bedtime_outlined,
      tagline: 'Updates only when you change places.',
      friendsSee: 'Friends see when you arrive somewhere new.',
      battery: '~1% per day',
    ),
    _ModeInfo(
      mode: SharingMode.balanced,
      label: 'Balanced',
      icon: Icons.balance_outlined,
      tagline: 'Updates every ~60s while moving.',
      friendsSee: 'Your dot lags real life by 1–2 minutes.',
      battery: '~2–4% per day',
    ),
    _ModeInfo(
      mode: SharingMode.live,
      label: 'Live',
      icon: Icons.gps_fixed_rounded,
      tagline: 'Updates every ~30s while driving.',
      friendsSee: 'Navigation-grade. For trips.',
      battery: '~5–8% per day',
    ),
  ];

  void _pick(SharingMode m) {
    if (m == _selected) return;
    setState(() => _selected = m);
    widget.onChanged(m);
  }

  @override
  Widget build(BuildContext context) {
    final info = _modes.firstWhere((m) => m.mode == _selected);
    return Scaffold(
      backgroundColor: context.gridColors.bg,
      appBar: AppBar(
        backgroundColor: context.gridColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Sharing mode',
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
            Container(
              decoration: BoxDecoration(
                color: context.gridColors.surface,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
                border: Border.all(color: context.gridColors.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: context.gridColors.surface2,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: context.gridColors.hairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final m in _modes)
                            Expanded(
                              child: _SharingModeChip(
                                info: m,
                                active: m.mode == _selected,
                                onTap: () => _pick(m.mode),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      info.tagline,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: context.gridColors.text,
                        letterSpacing: -0.005,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      info.friendsSee,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 13,
                        color: context.gridColors.text2,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.battery_5_bar_rounded,
                          size: 14,
                          color: context.gridColors.mint,
                        ),
                        const SizedBox(width: 6),
                        GridMono(
                          info.battery,
                          size: 11,
                          letterSpacing: 0.08,
                          color: context.gridColors.mint,
                        ),
                      ],
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
}

class _SharingModeChip extends StatelessWidget {
  const _SharingModeChip({
    required this.info,
    required this.active,
    required this.onTap,
  });

  final _ModeInfo info;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? context.gridColors.mintFaint : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: active
                ? Border.all(color: context.gridColors.mintSoft, width: 1)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                info.icon,
                size: 14,
                color: active
                    ? context.gridColors.mint
                    : context.gridColors.text3,
              ),
              const SizedBox(width: 6),
              Text(
                info.label,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.005,
                  color: active
                      ? context.gridColors.mint
                      : context.gridColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeInfo {
  const _ModeInfo({
    required this.mode,
    required this.label,
    required this.icon,
    required this.tagline,
    required this.friendsSee,
    required this.battery,
  });

  final SharingMode mode;
  final String label;
  final IconData icon;
  final String tagline;
  final String friendsSee;
  final String battery;
}
