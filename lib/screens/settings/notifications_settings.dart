import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../styles/tokens.dart';
import '../../widgets/grid/grid_mono.dart';
import '../../widgets/grid/grid_segmented.dart';

class NotificationSettingsPage extends StatefulWidget {
  @override
  _NotificationSettingsPageState createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  // Preserved existing prefs — mapped to the redesigned "People" section.
  // `showName`     -> "When someone shares with me"
  // `showAlerts`   -> "When a friend arrives at a place" (backend gated)
  // `showActions`  -> "When someone stops sharing" (backend gated)
  bool _showName = true;
  bool _showAlerts = true;
  bool _showActions = true;

  // New local-only UI state for the redesigned sections. Persistence for
  // these can be added once backend / platform plumbing is wired up.
  bool _quietHours = true;
  bool _vibrate = true;
  final String _quietStart = '9:00 PM';
  final String _quietEnd = '7:00 AM';
  final String _soundName = 'Soft chime';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showName = prefs.getBool('showName') ?? true;
      _showAlerts = prefs.getBool('showAlerts') ?? true;
      _showActions = prefs.getBool('showActions') ?? true;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showName', _showName);
    await prefs.setBool('showAlerts', _showAlerts);
    await prefs.setBool('showActions', _showActions);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GridTokens.bg,
      appBar: AppBar(
        backgroundColor: GridTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: GridTokens.text, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Notifications',
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
            _InfoCard(
              text:
                  'Notifications go through your server first — push tokens never reach Apple unencrypted.',
            ),
            const SizedBox(height: 4),

            // ── People ─────────────────────────────────────
            const GridSectionHeader(text: 'People'),
            _SettingsGroup(
              children: [
                _ToggleRow(
                  label: 'When someone shares with me',
                  value: _showName,
                  onChanged: (bool? value) {
                    setState(() {
                      _showName = value ?? false;
                    });
                    _savePreferences();
                  },
                ),
                _Divider(),
                // TODO: needs server-side support
                _ToggleRow(
                  label: 'When a friend arrives at a place',
                  value: _showAlerts,
                  enabled: false,
                  onChanged: (bool? value) {
                    setState(() {
                      _showAlerts = value ?? false;
                    });
                    _savePreferences();
                  },
                ),
                _Divider(),
                // TODO: needs server-side support
                _ToggleRow(
                  label: 'When someone stops sharing',
                  value: _showActions,
                  enabled: false,
                  onChanged: (bool? value) {
                    setState(() {
                      _showActions = value ?? false;
                    });
                    _savePreferences();
                  },
                ),
              ],
            ),

            // ── Quiet hours ────────────────────────────────
            const GridSectionHeader(text: 'Quiet hours'),
            _SettingsGroup(
              children: [
                _ToggleRow(
                  label: 'Quiet hours',
                  value: _quietHours,
                  onChanged: (bool? value) {
                    setState(() {
                      _quietHours = value ?? false;
                    });
                  },
                ),
                _Divider(),
                _TimeRow(
                  shortLabel: '9p',
                  label: 'Start',
                  time: _quietStart,
                  enabled: _quietHours,
                ),
                _Divider(),
                _TimeRow(
                  shortLabel: '7a',
                  label: 'End',
                  time: _quietEnd,
                  enabled: _quietHours,
                ),
              ],
            ),

            // ── Sound & vibration ──────────────────────────
            const GridSectionHeader(text: 'Sound & vibration'),
            _SettingsGroup(
              children: [
                _ValueRow(
                  label: 'Sound',
                  value: _soundName,
                ),
                _Divider(),
                _ToggleRow(
                  label: 'Vibrate',
                  value: _vibrate,
                  onChanged: (bool? value) {
                    setState(() {
                      _vibrate = value ?? false;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Local widgets — small atoms reused inside this screen.
// ─────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: GridTokens.mintFaint,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notifications_active_outlined,
            size: 18,
            color: GridTokens.mint,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.getFont(
                'Geist',
                color: GridTokens.text,
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.01,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GridTokens.surface,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: GridTokens.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 16),
      child: Divider(height: 1, thickness: 1, color: GridTokens.hairline),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.getFont(
                  'Geist',
                  color: GridTokens.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.01,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: value,
              onChanged: enabled ? (v) => onChanged(v) : null,
              thumbColor: WidgetStateProperty.all(Colors.white),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? GridTokens.mint
                    : GridTokens.surface3,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              trackOutlineColor:
                  WidgetStateProperty.all(Colors.transparent),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.shortLabel,
    required this.label,
    required this.time,
    this.enabled = true,
  });

  final String shortLabel;
  final String label;
  final String time;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: InkWell(
        onTap: enabled ? () {} : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: GridMono(
                  shortLabel,
                  color: GridTokens.text3,
                  size: 12,
                  letterSpacing: 0.04,
                  uppercase: false,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.getFont(
                    'Geist',
                    color: GridTokens.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.01,
                  ),
                ),
              ),
              GridMono(
                time,
                color: GridTokens.text2,
                size: 12,
                letterSpacing: 0.04,
                uppercase: false,
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: GridTokens.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.getFont(
                  'Geist',
                  color: GridTokens.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.01,
                ),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.getFont(
                'Geist',
                color: GridTokens.text2,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.01,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: GridTokens.text3),
          ],
        ),
      ),
    );
  }
}
