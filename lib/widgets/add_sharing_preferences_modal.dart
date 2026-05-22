import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/tokens.dart';
import '../styles/grid_colors.dart';
import 'grid/grid_button.dart';
import 'grid/grid_mono.dart';

/// Bottom sheet for adding a single sharing window. Simplified to a single
/// decision flow: days → time → optional name.
class AddSharingPreferenceModal extends StatefulWidget {
  /// onSave fires after Add is tapped. `startTime` / `endTime` are null
  /// when `isAllDay` is true. `label` may be empty — the list view will
  /// auto-summarise from days + time.
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
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
    'S',
  ];

  bool _isAllDay = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);

  @override
  void initState() {
    super.initState();
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
    if (!_hasDays) return false;
    if (_isAllDay) return true;
    final s = _startTime.hour * 60 + _startTime.minute;
    final e = _endTime.hour * 60 + _endTime.minute;
    return e > s;
  }

  Future<void> _pickTime(bool isStart) async {
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

  void _quickPreset(List<int> days, TimeOfDay s, TimeOfDay e, bool allDay) {
    setState(() {
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
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPresetsRow(),
                        const SizedBox(height: 20),
                        _buildDaysSection(),
                        const SizedBox(height: 20),
                        _buildTimeSection(),
                        const SizedBox(height: 20),
                        _buildLabelField(),
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
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
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

  Widget _buildPresetsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _PresetChip(
            label: 'Workdays 9–5',
            onTap: () => _quickPreset(
              const [0, 1, 2, 3, 4],
              const TimeOfDay(hour: 9, minute: 0),
              const TimeOfDay(hour: 17, minute: 0),
              false,
            ),
          ),
          const SizedBox(width: 6),
          _PresetChip(
            label: 'Weekends',
            onTap: () => _quickPreset(
              const [5, 6],
              const TimeOfDay(hour: 0, minute: 0),
              const TimeOfDay(hour: 23, minute: 59),
              true,
            ),
          ),
          const SizedBox(width: 6),
          _PresetChip(
            label: 'Evenings',
            onTap: () => _quickPreset(
              const [0, 1, 2, 3, 4, 5, 6],
              const TimeOfDay(hour: 18, minute: 0),
              const TimeOfDay(hour: 23, minute: 0),
              false,
            ),
          ),
        ],
      ),
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
                  final fill = !_hasDays;
                  for (var i = 0; i < 7; i++) {
                    _selectedDays[i] = fill;
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
        Row(
          children: [
            GridMono(
              'TIME',
              size: 10,
              color: context.gridColors.text3,
              letterSpacing: 0.12,
            ),
            const Spacer(),
            _AllDayChip(
              active: _isAllDay,
              onTap: () => setState(() => _isAllDay = !_isAllDay),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (!_isAllDay)
          _TimeRangeRow(
            start: _startTime,
            end: _endTime,
            onTapStart: () => _pickTime(true),
            onTapEnd: () => _pickTime(false),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: context.gridColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.gridColors.hairline),
            ),
            child: Text(
              'Shares for the entire day',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.gridColors.text2,
              ),
            ),
          ),
        if (!_isAllDay && _hasDays && !_isValid)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'End time must be after start.',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 12,
                color: context.gridColors.danger,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLabelField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridMono(
          'NAME (OPTIONAL)',
          size: 10,
          color: context.gridColors.text3,
          letterSpacing: 0.12,
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _labelController,
          focusNode: _labelFocus,
          autocorrect: true,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: context.gridColors.mint,
          cursorWidth: 2,
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: context.gridColors.text,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            hintText: 'e.g. Work hours',
            hintStyle: GoogleFonts.getFont(
              'Geist',
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: context.gridColors.text3,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: context.gridColors.hairline),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide:
                  BorderSide(color: context.gridColors.mint, width: 1.5),
            ),
          ),
        ),
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
    required this.label,
    required this.onTap,
  });

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
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.gridColors.hairline),
          ),
          child: Text(
            label,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.005,
              color: context.gridColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.active, required this.onTap});

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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? context.gridColors.mintFaint : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? context.gridColors.mint : context.gridColors.hairline,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Text(
            'All day',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? context.gridColors.mint : context.gridColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeRangeRow extends StatelessWidget {
  const _TimeRangeRow({
    required this.start,
    required this.end,
    required this.onTapStart,
    required this.onTapEnd,
  });

  final TimeOfDay start;
  final TimeOfDay end;
  final VoidCallback onTapStart;
  final VoidCallback onTapEnd;

  String _fmt(TimeOfDay t) {
    final mm = t.minute.toString().padLeft(2, '0');
    final isPm = t.hour >= 12;
    final h12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    return '$h12:$mm ${isPm ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.gridColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.gridColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TimePart(label: _fmt(start), onTap: onTapStart),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: context.gridColors.text3,
            ),
          ),
          Expanded(
            child: _TimePart(label: _fmt(end), onTap: onTapEnd),
          ),
        ],
      ),
    );
  }
}

class _TimePart extends StatelessWidget {
  const _TimePart({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.01,
              color: context.gridColors.text,
            ),
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
