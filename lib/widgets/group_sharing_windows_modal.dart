import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/sharing_preferences.dart';
import '../models/sharing_window.dart';
import '../repositories/sharing_preferences_repository.dart';
import '../services/in_app_notifier.dart';
import '../styles/grid_colors.dart';
import '../styles/tokens.dart';
import 'add_sharing_preferences_modal.dart';
import 'grid/grid_button.dart';
import 'grid/grid_mono.dart';
import 'grid/grid_segmented.dart';
import 'grid/grid_sheet.dart';

/// Bottom sheet that lists existing sharing windows for a group and lets
/// the user toggle, edit, or delete them, plus pause sharing entirely.
class GroupSharingWindowsModal extends StatefulWidget {
  final String roomId;
  final String groupName;
  final SharingPreferencesRepository sharingPreferencesRepository;

  const GroupSharingWindowsModal({
    super.key,
    required this.roomId,
    required this.groupName,
    required this.sharingPreferencesRepository,
  });

  @override
  State<GroupSharingWindowsModal> createState() =>
      _GroupSharingWindowsModalState();
}

class _GroupSharingWindowsModalState extends State<GroupSharingWindowsModal> {
  bool _isLoading = true;
  bool _activeSharing = true;
  List<SharingWindow> _windows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await widget.sharingPreferencesRepository
          .getSharingPreferences(widget.roomId, 'group');
      if (!mounted) return;
      setState(() {
        _activeSharing = prefs?.activeSharing ?? true;
        _windows = prefs?.shareWindows?.toList() ?? <SharingWindow>[];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      InAppNotifier.instance.show(
        title: 'Could not load sharing windows',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  Future<void> _persist({
    required bool activeSharing,
    required List<SharingWindow> windows,
  }) async {
    await widget.sharingPreferencesRepository.setSharingPreferences(
      SharingPreferences(
        targetId: widget.roomId,
        targetType: 'group',
        activeSharing: activeSharing,
        shareWindows: windows,
      ),
    );
  }

  Future<void> _toggleActiveSharing(bool v) async {
    final prev = _activeSharing;
    setState(() => _activeSharing = v);
    try {
      await _persist(activeSharing: v, windows: _windows);
      if (!mounted) return;
      InAppNotifier.instance.show(
        title: v ? 'Sharing resumed for group' : 'Sharing paused for group',
        message: v
            ? 'Members will see your location based on your windows.'
            : 'Resume any time from this menu.',
        variant: InAppNotificationVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _activeSharing = prev);
      InAppNotifier.instance.show(
        title: 'Could not update sharing',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  Future<void> _toggleWindowActive(int index, bool v) async {
    final prev = _windows[index];
    final updated = SharingWindow(
      label: prev.label,
      days: prev.days,
      isAllDay: prev.isAllDay,
      startTime: prev.startTime,
      endTime: prev.endTime,
      isActive: v,
    );
    setState(() => _windows[index] = updated);
    try {
      await _persist(activeSharing: _activeSharing, windows: _windows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _windows[index] = prev);
      InAppNotifier.instance.show(
        title: 'Could not update window',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  Future<void> _deleteWindow(int index) async {
    final removed = _windows[index];
    setState(() => _windows.removeAt(index));
    try {
      await _persist(activeSharing: _activeSharing, windows: _windows);
      if (!mounted) return;
      InAppNotifier.instance.show(
        title: 'Sharing window removed',
        message: 'You can add a new window any time.',
        variant: InAppNotificationVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _windows.insert(index, removed));
      InAppNotifier.instance.show(
        title: 'Could not delete window',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  void _openAddOrEdit({SharingWindow? existing, int? index}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: AddSharingPreferenceModal(
            initial: existing,
            onSave: (label, selectedDays, isAllDay, startTime, endTime) async {
              final next = SharingWindow(
                label: label,
                days: [
                  for (var i = 0; i < selectedDays.length; i++)
                    if (selectedDays[i]) i,
                ],
                isAllDay: isAllDay,
                startTime: (isAllDay || startTime == null)
                    ? null
                    : '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                endTime: (isAllDay || endTime == null)
                    ? null
                    : '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
                isActive: existing?.isActive ?? true,
              );

              final isEdit = index != null;
              final prevList = List<SharingWindow>.from(_windows);
              setState(() {
                if (isEdit) {
                  _windows[index] = next;
                } else {
                  _windows.add(next);
                }
              });
              try {
                await _persist(
                  activeSharing: _activeSharing,
                  windows: _windows,
                );
                if (!mounted) return;
                InAppNotifier.instance.show(
                  title: isEdit
                      ? 'Sharing window updated'
                      : 'Sharing window added',
                  message: isEdit
                      ? 'Your changes are saved.'
                      : 'Friends in this group will see your location during this window.',
                  variant: InAppNotificationVariant.success,
                );
              } catch (e) {
                if (!mounted) return;
                setState(() => _windows = prevList);
                InAppNotifier.instance.show(
                  title: 'Could not save window',
                  message: '$e',
                  variant: InAppNotificationVariant.error,
                );
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _isLoading
        ? 'Loading windows for ${widget.groupName}'
        : '${_windows.length} window${_windows.length == 1 ? '' : 's'} · ${widget.groupName}';
    return GridSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridSheetHeader(
            title: 'Sharing windows',
            subtitle: subtitle,
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: _isLoading
                ? _buildLoadingState()
                : _buildBody(),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor:
                  AlwaysStoppedAnimation<Color>(context.gridColors.mint),
            ),
          ),
          const SizedBox(height: 14),
          GridMono(
            'LOADING',
            size: 11,
            color: context.gridColors.text3,
            letterSpacing: 0.12,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
            child: _buildActiveSharingCard(),
          ),
          if (_windows.isEmpty)
            _buildEmptyState()
          else ...[
            const GridSectionHeader(text: 'WINDOWS'),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: context.gridColors.surface,
                  borderRadius: BorderRadius.circular(GridTokens.rMd),
                  border: Border.all(color: context.gridColors.hairline),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _windows.length; i++) ...[
                      _WindowTile(
                        window: _windows[i],
                        enabled: _activeSharing,
                        onTap: () => _openAddOrEdit(
                          existing: _windows[i],
                          index: i,
                        ),
                        onToggle: (v) => _toggleWindowActive(i, v),
                        onDelete: () => _deleteWindow(i),
                      ),
                      if (i < _windows.length - 1)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: context.gridColors.hairline,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveSharingCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
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
                  'Sharing active',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.gridColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _activeSharing
                      ? 'Location flows to this group during your windows.'
                      : 'Sharing is paused for this group.',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 12,
                    color: context.gridColors.text2,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _activeSharing,
            activeColor: context.gridColors.mint,
            onChanged: _toggleActiveSharing,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.gridColors.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: context.gridColors.hairline),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.schedule_rounded,
                size: 32,
                color: context.gridColors.text3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No sharing windows yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.01,
                color: context.gridColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add a window to share your location with this group on a schedule.',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                color: context.gridColors.text2,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        width: double.infinity,
        child: GridButton(
          label: 'Add window',
          onPressed: () => _openAddOrEdit(),
        ),
      ),
    );
  }
}

class _WindowTile extends StatelessWidget {
  const _WindowTile({
    required this.window,
    required this.enabled,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final SharingWindow window;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final summary = _summarise(window);
    final dim = !window.isActive || !enabled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      window.label.isNotEmpty ? window.label : summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: dim
                            ? context.gridColors.text3
                            : context.gridColors.text,
                      ),
                    ),
                    if (window.label.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 12,
                          color: context.gridColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch.adaptive(
                value: window.isActive,
                activeColor: context.gridColors.mint,
                onChanged: enabled ? onToggle : null,
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: context.gridColors.text3,
                ),
                tooltip: 'Delete window',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _summarise(SharingWindow w) {
    const dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = [...w.days]..sort();
    String daysPart;
    if (sorted.isEmpty) {
      daysPart = 'No days';
    } else if (sorted.length == 7) {
      daysPart = 'Every day';
    } else if (sorted.length == 5 && sorted.every((d) => d >= 0 && d <= 4)) {
      daysPart = 'Workdays';
    } else if (sorted.length == 2 && sorted[0] == 5 && sorted[1] == 6) {
      daysPart = 'Weekends';
    } else {
      daysPart = sorted.map((d) => dayShort[d]).join(', ');
    }
    final timePart = w.isAllDay
        ? 'All day'
        : '${_fmtClock(w.startTime)} – ${_fmtClock(w.endTime)}';
    return '$daysPart  ·  $timePart';
  }

  String _fmtClock(String? hhmm) {
    if (hhmm == null || hhmm.length < 4) return '';
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? parts[1] : '00';
    final isPm = h >= 12;
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m ${isPm ? 'PM' : 'AM'}';
  }
}
