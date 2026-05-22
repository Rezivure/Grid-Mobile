import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/tokens.dart';
import '../styles/grid_colors.dart';
import 'grid/grid_button.dart';
import 'grid/grid_mono.dart';

/// Bottom sheet for adding a single sharing window. Restyled to the Grid
/// 2.0 dark token system (was tracking system light/dark via the
/// ColorScheme, which looked alien against the rest of the now-dark app).
class AddSharingPreferenceModal extends StatefulWidget {
  /// onSave fires after Add is tapped. `startTime` / `endTime` are null
  /// when `isAllDay` is true.
  final void Function(
    String label,
    List<bool> selectedDays,
    bool isAllDay,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  ) onSave;

  const AddSharingPreferenceModal({
    Key? key,
    required this.onSave,
  }) : super(key: key);

  @override
  State<AddSharingPreferenceModal> createState() =>
      _AddSharingPreferenceModalState();
}

class _AddSharingPreferenceModalState
    extends State<AddSharingPreferenceModal> {
  final TextEditingController _labelController = TextEditingController();
  final FocusNode _labelFocus = FocusNode();
  final List<bool> _selectedDays = List.generate(7, (_) => false);

  static const List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  bool _isAllDay = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);

  @override
  void initState() {
    super.initState();
    _labelController.addListener(() => setState(() {}));
    _labelFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _labelController.dispose();
    _labelFocus.dispose();
    super.dispose();
  }

  bool get _hasDays => _selectedDays.contains(true);

  bool get _isValid {
    if (_labelController.text.trim().isEmpty) return false;
    if (!_hasDays) return false;
    if (_isAllDay) return true;
    final s = _startTime.hour * 60 + _startTime.minute;
    final e = _endTime.hour * 60 + _endTime.minute;
    return e > s;
  }

  Future<void> _pickTime(bool isStart) async {
    // Theme the system picker so it doesn't pop a Material-3 light dialog
    // in the middle of a dark sheet.
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: context.gridColors.mint,
              onPrimary: const Color(0xFF04201A),
              surface: context.gridColors.surface,
              onSurface: context.gridColors.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _quickPreset(String label, List<int> days, TimeOfDay s, TimeOfDay e,
      bool allDay) {
    setState(() {
      _labelController.text = label;
      for (var i = 0; i < 7; i++) {
        _selectedDays[i] = days.contains(i);
      }
      _isAllDay = allDay;
      _startTime = s;
      _endTime = e;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Material(
      color: Colors.transparent,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: BoxDecoration(
            color: context.gridColors.bg,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(GridTokens.r2Xl),
            ),
            border: Border(
              top: BorderSide(color: context.gridColors.hairline),
              left: BorderSide(color: context.gridColors.hairline),
              right: BorderSide(color: context.gridColors.hairline),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHandle(),
                _buildHeader(),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabelField(),
                        const SizedBox(height: 18),
                        _buildPresetsRow(),
                        const SizedBox(height: 18),
                        _buildDaysSection(),
                        const SizedBox(height: 18),
                        _buildTimeSection(),
                      ],
                    ),
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: context.gridColors.hairlineStrong,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.gridColors.mintFaint,
              borderRadius: BorderRadius.circular(GridTokens.rSm),
              border: Border.all(color: context.gridColors.mintSoft),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.schedule_rounded,
              size: 18,
              color: context.gridColors.mint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New sharing window',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.015,
                    color: context.gridColors.text,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pick when your location is shared.',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 12.5,
                    color: context.gridColors.text2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: context.gridColors.text2,
              size: 22,
            ),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelField() {
    final hasContent = _labelController.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridMono(
          'LABEL',
          size: 10,
          color: context.gridColors.text3,
          letterSpacing: 0.12,
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.gridColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _labelFocus.hasFocus
                  ? context.gridColors.mint
                  : context.gridColors.hairline,
              width: _labelFocus.hasFocus ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.label_outline_rounded,
                size: 18,
                color: context.gridColors.text3,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _labelController,
                  focusNode: _labelFocus,
                  autocorrect: true,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: context.gridColors.mint,
                  cursorWidth: 2,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: context.gridColors.text,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    filled: false,
                    fillColor: Colors.transparent,
                    hintText: hasContent ? null : 'Work hours, Trip, Gym…',
                    hintStyle: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: context.gridColors.text3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridMono(
          'QUICK START',
          size: 10,
          color: context.gridColors.text3,
          letterSpacing: 0.12,
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _PresetChip(
                icon: Icons.work_outline_rounded,
                label: 'Workdays 9–5',
                onTap: () => _quickPreset(
                  'Work hours',
                  const [0, 1, 2, 3, 4],
                  const TimeOfDay(hour: 9, minute: 0),
                  const TimeOfDay(hour: 17, minute: 0),
                  false,
                ),
              ),
              const SizedBox(width: 8),
              _PresetChip(
                icon: Icons.weekend_outlined,
                label: 'Weekends',
                onTap: () => _quickPreset(
                  'Weekends',
                  const [5, 6],
                  const TimeOfDay(hour: 0, minute: 0),
                  const TimeOfDay(hour: 23, minute: 59),
                  true,
                ),
              ),
              const SizedBox(width: 8),
              _PresetChip(
                icon: Icons.bedtime_outlined,
                label: 'Evenings',
                onTap: () => _quickPreset(
                  'Evenings',
                  const [0, 1, 2, 3, 4, 5, 6],
                  const TimeOfDay(hour: 18, minute: 0),
                  const TimeOfDay(hour: 23, minute: 0),
                  false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDaysSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GridMono(
              'DAYS',
              size: 10,
              color: context.gridColors.text3,
              letterSpacing: 0.12,
            ),
            const Spacer(),
            _MiniLink(
              label: _hasDays ? 'Clear' : 'Every day',
              onTap: () {
                setState(() {
                  if (_hasDays) {
                    for (var i = 0; i < 7; i++) {
                      _selectedDays[i] = false;
                    }
                  } else {
                    for (var i = 0; i < 7; i++) {
                      _selectedDays[i] = true;
                    }
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < 7; i++) ...[
              Expanded(
                child: _DayChip(
                  label: _weekdays[i],
                  active: _selectedDays[i],
                  onTap: () => setState(
                      () => _selectedDays[i] = !_selectedDays[i]),
                ),
              ),
              if (i < 6) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildTimeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridMono(
          'TIME',
          size: 10,
          color: context.gridColors.text3,
          letterSpacing: 0.12,
        ),
        const SizedBox(height: 10),
        // All-day toggle row.
        _ToggleRow(
          title: 'All day',
          subtitle: 'Share for the entire day on the selected days',
          value: _isAllDay,
          onChanged: (v) => setState(() => _isAllDay = v),
        ),
        if (!_isAllDay) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label: 'Starts',
                  time: _startTime,
                  onTap: () => _pickTime(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeButton(
                  label: 'Ends',
                  time: _endTime,
                  onTap: () => _pickTime(false),
                ),
              ),
            ],
          ),
          if (!_isValid && _labelController.text.trim().isNotEmpty &&
              _hasDays)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 13,
                    color: context.gridColors.danger,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'End time must be after start.',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 12,
                      color: context.gridColors.danger,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: GridButton(
              label: 'Cancel',
              style: GridButtonStyle.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: GridButton(
              label: 'Add window',
              icon: Icons.add_rounded,
              onPressed: _isValid
                  ? () {
                      widget.onSave(
                        _labelController.text.trim(),
                        _selectedDays,
                        _isAllDay,
                        _isAllDay ? null : _startTime,
                        _isAllDay ? null : _endTime,
                      );
                      Navigator.of(context).pop();
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Small bits
// ─────────────────────────────────────────────────────────────────────

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rSm),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? context.gridColors.mintFaint : context.gridColors.surface,
            borderRadius: BorderRadius.circular(GridTokens.rSm),
            border: Border.all(
              color: active ? context.gridColors.mint : context.gridColors.hairline,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.005,
              color: active ? context.gridColors.mint : context.gridColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.gridColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.gridColors.hairlineStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: context.gridColors.mint),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.005,
                  color: context.gridColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: context.gridColors.surface,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: context.gridColors.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: context.gridColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 12.5,
                        color: context.gridColors.text2,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch.adaptive(
                value: value,
                activeColor: context.gridColors.mint,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mm = time.minute.toString().padLeft(2, '0');
    final isPm = time.hour >= 12;
    final h12 =
        time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
    final clock = '$h12:$mm ${isPm ? 'PM' : 'AM'}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.gridColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.gridColors.hairline, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridMono(
                label.toUpperCase(),
                size: 10,
                color: context.gridColors.text3,
                letterSpacing: 0.12,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 15,
                    color: context.gridColors.mint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    clock,
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.01,
                      color: context.gridColors.text,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniLink extends StatelessWidget {
  const _MiniLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: context.gridColors.mint,
      ),
      child: Text(
        label,
        style: GoogleFonts.getFont(
          'Geist',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.gridColors.mint,
        ),
      ),
    );
  }
}
