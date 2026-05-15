import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/add_sharing_preferences_modal.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_status_pill.dart';
import 'package:grid_frontend/widgets/user_avatar_bloc.dart';

import '../models/sharing_window.dart';
import '../models/sharing_preferences.dart';
import '../repositories/sharing_preferences_repository.dart';

/// Contact profile modal. Redesigned per §5.9 of the design handoff:
/// 280pt map hero, identity row overlapping the hero, status pill strip,
/// mutual-sharing card, 4-button action grid, shared-groups chips.
class ContactProfileModal extends StatefulWidget {
  final ContactDisplay contact;
  final RoomService roomService;
  final SharingPreferencesRepository sharingPreferencesRepo;

  const ContactProfileModal({
    Key? key,
    required this.contact,
    required this.roomService,
    required this.sharingPreferencesRepo,
  }) : super(key: key);

  @override
  _ContactProfileModalState createState() => _ContactProfileModalState();
}

class _ContactProfileModalState extends State<ContactProfileModal> {
  bool _copied = false;
  bool _isLoading = true;
  bool _alwaysShare = false;

  /// All device keys (fetched from the RoomService)
  late Map<String, Map<String, String>> _allOtherDeviceKeys;

  /// List of sharing windows loaded from the DB
  List<SharingWindow> _sharingWindows = [];

  /// Whether we're currently editing sharing preferences (for showing X buttons)
  bool _isEditingPreferences = false;

  /// Whether the device keys section is expanded
  bool _isDeviceKeysExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceKeys();
  }

  Future<void> _loadDeviceKeys() async {
    try {
      // Get device keys directly from RoomService
      final keyData = widget.roomService.getUserDeviceKeys(widget.contact.userId);
      setState(() {
        _allOtherDeviceKeys = keyData;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading device keys: $e');
      setState(() {
        _allOtherDeviceKeys = {};
        _isLoading = false;
      });
    }

    await _loadSharingPreferences();
  }

  Future<void> _loadSharingPreferences() async {
    try {
      // Try 'user' type first (new format), then fall back to 'contact' for backwards compatibility
      var prefs = await widget.sharingPreferencesRepo.getSharingPreferences(widget.contact.userId, 'user');
      prefs ??= await widget.sharingPreferencesRepo.getSharingPreferences(widget.contact.userId, 'contact');

      setState(() {
        // Default to true for new contacts if no preferences exist
        _alwaysShare = prefs?.activeSharing ?? true;
        _sharingWindows = prefs?.shareWindows ?? [];
      });
    } catch (e) {
      print('Error loading sharing preferences: $e');
      setState(() {
        _alwaysShare = true; // Default to sharing for new contacts
        _sharingWindows = [];
      });
    }
  }

  Future<void> _saveToDatabase() async {
    final preferences = SharingPreferences(
      targetId: widget.contact.userId,
      targetType: 'user', // Use 'user' to match what sync_manager creates
      activeSharing: _alwaysShare,
      shareWindows: _sharingWindows,
    );
    await widget.sharingPreferencesRepo.setSharingPreferences(preferences);
  }

  void _showExpandedAvatar(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: Hero(
                  tag: 'contact_avatar_${widget.contact.userId}',
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.width * 0.8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: GridTokens.surface,
                    ),
                    child: ClipOval(
                      child: UserAvatarBloc(
                        userId: widget.contact.userId,
                        size: MediaQuery.of(context).size.width * 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? getRoomId(String userId) {
    // This method is simplified since we're not using it for device keys anymore
    return null;
  }

  void _openAddSharingPreferenceModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: AddSharingPreferenceModal(
            onSave: (label, selectedDays, isAllDay, startTime, endTime) async {
              final newWindow = SharingWindow(
                label: label,
                days: _daysToIntList(selectedDays),
                isAllDay: isAllDay,
                startTime: (isAllDay || startTime == null)
                    ? null
                    : '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                endTime: (isAllDay || endTime == null)
                    ? null
                    : '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
                isActive: true,
              );

              setState(() {
                _sharingWindows.add(newWindow);
              });
              await _saveToDatabase();
            },
          ),
        );
      },
    );
  }

  List<int> _daysToIntList(List<bool> selectedDays) {
    final days = <int>[];
    for (int i = 0; i < selectedDays.length; i++) {
      if (selectedDays[i]) days.add(i);
    }
    return days;
  }

  // ────────────────────────────────────────────────────────────────────
  // build
  // ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final userLocalpart = widget.contact.userId.split(':')[0].replaceFirst('@', '');
    final currentHomeserver = widget.roomService.getMyHomeserver();
    final showFullMatrixId = utils.isCustomHomeserver(currentHomeserver);
    final handle = showFullMatrixId
        ? widget.contact.userId
        : utils.formatUserId(widget.contact.userId);
    final firstName = widget.contact.displayName.split(' ').first;

    return Container(
      decoration: const BoxDecoration(
        color: GridTokens.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(GridTokens.r2Xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grab handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: GridTokens.text4,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 280pt map hero with the focused pin.
                  _buildMapHero(),

                  // Identity row overlaps the hero by 32pt.
                  Transform.translate(
                    offset: const Offset(0, -32),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      child: _buildIdentityRow(userLocalpart, handle, showFullMatrixId),
                    ),
                  ),

                  // Pull subsequent content up so we don't have a 32pt gap.
                  Transform.translate(
                    offset: const Offset(0, -32),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 14),
                          _buildStatusRow(),
                          const SizedBox(height: 18),
                          _buildMutualSharingCard(firstName),
                          const SizedBox(height: 14),
                          _buildActionGrid(),
                          const SizedBox(height: 22),
                          _buildSharedGroups(),
                          if (!_alwaysShare) ...[
                            const SizedBox(height: 22),
                            _buildSectionLabel('SHARING WINDOWS'),
                            const SizedBox(height: 10),
                            _buildSharingWindows(),
                          ],
                          const SizedBox(height: 22),
                          _buildSectionLabel('SECURITY'),
                          const SizedBox(height: 10),
                          _buildSecurityCard(),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // hero
  // ────────────────────────────────────────────────────────────────────

  Widget _buildMapHero() {
    // We don't have a real map widget in scope here (no controller, no route
    // service exposed to this modal), so we render a stylized dark surface
    // that matches the design handoff's map aesthetic — a faint grid pattern
    // plus the focused pin in the center, with a gradient fade to bg at the
    // bottom edge.
    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          // Base surface
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [GridTokens.mapBg, GridTokens.mapLand],
                ),
              ),
            ),
          ),
          // Faint grid overlay
          Positioned.fill(
            child: CustomPaint(
              painter: _MapGridPainter(),
            ),
          ),
          // Gradient fade at the bottom into bg, so the identity row floats.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 96,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    GridTokens.bg.withAlpha(0),
                    GridTokens.bg,
                  ],
                ),
              ),
            ),
          ),
          // Focused pin
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: _focusedPin(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _focusedPin() {
    final live = _alwaysShare;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Floating label chip above the pin
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: GridTokens.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: GridTokens.hairlineStrong, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.contact.displayName.split(' ').first,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GridTokens.text,
                ),
              ),
              const SizedBox(width: 6),
              GridMono(
                widget.contact.lastSeen.isEmpty ? 'now' : widget.contact.lastSeen,
                size: 9,
                color: GridTokens.text3,
                letterSpacing: 0.06,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Pin: ringed avatar with downward tail
        SizedBox(
          width: 64,
          height: 80,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              GridAvatar(
                name: widget.contact.displayName,
                size: 48,
                ring: true,
                status: live ? GridAvatarStatus.live : GridAvatarStatus.paused,
              ),
              Positioned(
                bottom: 6,
                child: CustomPaint(
                  size: const Size(14, 10),
                  painter: _PinTailPainter(
                    color: live ? GridTokens.mint : GridTokens.hairlineStrong,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // identity row
  // ────────────────────────────────────────────────────────────────────

  Widget _buildIdentityRow(String userLocalpart, String handle, bool showFullMatrixId) {
    final live = _alwaysShare;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 72pt avatar in 3pt bg padding.
        GestureDetector(
          onTap: () => _showExpandedAvatar(context),
          child: Hero(
            tag: 'contact_avatar_${widget.contact.userId}',
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: GridTokens.bg,
              ),
              child: ClipOval(
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: UserAvatarBloc(
                    userId: widget.contact.userId,
                    size: 72,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.contact.displayName,
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.02,
                          color: GridTokens.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (live) ...[
                      const SizedBox(width: 8),
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: GridLiveBadge(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: GridMono(
                        '@$handle',
                        uppercase: false,
                        size: 12,
                        color: GridTokens.text3,
                        letterSpacing: 0.02,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _CopyButton(
                      copied: _copied,
                      onTap: () {
                        final textToCopy = showFullMatrixId
                            ? widget.contact.userId.substring(1)
                            : userLocalpart;
                        Clipboard.setData(ClipboardData(text: textToCopy));
                        setState(() => _copied = true);
                        Future.delayed(const Duration(seconds: 2), () {
                          if (mounted) setState(() => _copied = false);
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // status pill row
  // ────────────────────────────────────────────────────────────────────

  Widget _buildStatusRow() {
    // We don't have access to motion/speed/distance/bearing data in this
    // widget's inputs, so we render the pills we can ground in real state:
    // the active/paused state derived from `_alwaysShare` and the "updated"
    // age from `contact.lastSeen`.
    final live = _alwaysShare;
    final updatedLabel = widget.contact.lastSeen.isEmpty
        ? 'JUST NOW'
        : 'UPDATED ${widget.contact.lastSeen}';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        GridStatusPill(
          label: live ? 'SHARING' : 'PAUSED',
          kind: live ? GridStatusKind.live : GridStatusKind.paused,
        ),
        _MonoPill(label: updatedLabel),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // mutual sharing card
  // ────────────────────────────────────────────────────────────────────

  Widget _buildMutualSharingCard(String firstName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: GridTokens.mintFaint,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: GridTokens.mintSoft, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: GridTokens.mintSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.verified_user_rounded, size: 13, color: GridTokens.mint),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mutual sharing',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.01,
                    color: GridTokens.text,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: GridTokens.mintSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: GridMono('E2EE', color: GridTokens.mint, size: 9, letterSpacing: 0.12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ShareToggle(
                  label: 'You',
                  arrow: '→',
                  other: firstName,
                  value: _alwaysShare,
                  onChanged: (value) async {
                    // Wire to the existing share-prefs flow used by the
                    // legacy "always share" switch — flips activeSharing on
                    // the user's SharingPreferences row.
                    setState(() => _alwaysShare = value);
                    await _saveToDatabase();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                // TODO: needs backend — there is no incoming-share toggle
                // accessor on RoomService / SharingPreferencesRepository
                // for the contact's direction toward us. Render as
                // read-only "on" since the contact relationship exists.
                child: _ShareToggle(
                  label: firstName,
                  arrow: '→',
                  other: 'You',
                  value: true,
                  onChanged: null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // 4-button action grid
  // ────────────────────────────────────────────────────────────────────

  Widget _buildActionGrid() {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Message',
            // TODO: needs backend — no DM/chat surface wired into this
            // widget. Wire to room_service.directMessage(...) when surfaced.
            onTap: null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.history_rounded,
            label: 'History',
            // TODO: needs backend — location history modal isn't routed
            // from this widget. Wire when surfaced.
            onTap: null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.alt_route_rounded,
            label: 'Route',
            // TODO: needs backend
            onTap: null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.notifications_none_rounded,
            label: 'Alerts',
            // TODO: needs backend
            onTap: null,
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // shared groups
  // ────────────────────────────────────────────────────────────────────

  Widget _buildSharedGroups() {
    // We don't pull shared-groups from the room service in this widget
    // (it isn't passed in and adding a fetch would expand logic surface).
    // Render the section label always; chip row stays empty for now.
    // TODO: needs backend — surface shared-room list for this contact.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('SHARED GROUPS'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: GridTokens.surface,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.hairline, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.groups_2_outlined, size: 18, color: GridTokens.text3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No shared groups yet',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: GridTokens.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // section label
  // ────────────────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String text, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: GridMono(text, size: 10, color: GridTokens.text3, letterSpacing: 0.12),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // sharing windows (kept for when _alwaysShare is off)
  // ────────────────────────────────────────────────────────────────────

  Widget _buildSharingWindows() {
    if (_sharingWindows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GridTokens.surface,
          borderRadius: BorderRadius.circular(GridTokens.rMd),
          border: Border.all(color: GridTokens.hairline, width: 1),
        ),
        child: Column(
          children: [
            Icon(Icons.schedule_outlined, size: 28, color: GridTokens.text3),
            const SizedBox(height: 8),
            Text(
              'No sharing windows set',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: GridTokens.text2,
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openAddSharingPreferenceModal,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: GridTokens.mintSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 14, color: GridTokens.mint),
                      const SizedBox(width: 6),
                      Text(
                        'Add window',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: GridTokens.mint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _isEditingPreferences = !_isEditingPreferences;
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _isEditingPreferences ? 'Done' : 'Edit',
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GridTokens.mint,
                ),
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._sharingWindows.map((window) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: () async {
                      if (!_isEditingPreferences) {
                        final index = _sharingWindows.indexOf(window);
                        final updatedWindow = SharingWindow(
                          label: window.label,
                          days: window.days,
                          isAllDay: window.isAllDay,
                          startTime: window.startTime,
                          endTime: window.endTime,
                          isActive: !window.isActive,
                        );
                        setState(() {
                          _sharingWindows[index] = updatedWindow;
                        });
                        await _saveToDatabase();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: window.isActive ? GridTokens.mintSoft : GridTokens.surface2,
                        border: Border.all(
                          color: window.isActive ? GridTokens.mint : GridTokens.hairline,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        window.label,
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: window.isActive ? GridTokens.mint : GridTokens.text2,
                        ),
                      ),
                    ),
                  ),
                  if (_isEditingPreferences)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () async {
                          setState(() {
                            _sharingWindows.remove(window);
                          });
                          await _saveToDatabase();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: GridTokens.danger,
                          ),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              );
            }),
            GestureDetector(
              onTap: _openAddSharingPreferenceModal,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: GridTokens.surface2,
                  border: Border.all(color: GridTokens.hairlineStrong, width: 1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 14, color: GridTokens.mint),
                    const SizedBox(width: 6),
                    Text(
                      'Add window',
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: GridTokens.mint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // security (device keys) — kept, but restyled
  // ────────────────────────────────────────────────────────────────────

  Widget _buildSecurityCard() {
    return Container(
      decoration: BoxDecoration(
        color: GridTokens.surface,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: GridTokens.hairline, width: 1),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isDeviceKeysExpanded = !_isDeviceKeysExpanded;
                });
              },
              borderRadius: BorderRadius.circular(GridTokens.rMd),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: GridTokens.mintFaint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.shield_outlined, size: 18, color: GridTokens.mint),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Encryption keys',
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: GridTokens.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Verify your contact\'s identity',
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: GridTokens.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isDeviceKeysExpanded ? Icons.expand_less : Icons.expand_more,
                      color: GridTokens.text3,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isDeviceKeysExpanded) ...[
            const Divider(height: 1, color: GridTokens.hairline),
            Padding(
              padding: const EdgeInsets.all(14),
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: GridTokens.mint),
                      ),
                    )
                  : _buildDeviceKeysList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceKeysList() {
    final allDeviceKeys = _allOtherDeviceKeys;

    if (allDeviceKeys.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: GridTokens.surface2,
          borderRadius: BorderRadius.circular(GridTokens.rMd),
        ),
        child: Column(
          children: [
            const Icon(Icons.shield_outlined, size: 36, color: GridTokens.text3),
            const SizedBox(height: 10),
            Text(
              'No security keys yet',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: GridTokens.text2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Keys appear here once the contact is verified.',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: GridTokens.text3,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: GridTokens.mintFaint,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.mintSoft, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: GridTokens.mint, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Compare these keys with the ones in your contact's settings.",
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: GridTokens.mint,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...allDeviceKeys.entries.map((entry) {
          final deviceId = entry.key;
          final keys = entry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: GridTokens.surface2,
              borderRadius: BorderRadius.circular(GridTokens.rMd),
              border: Border.all(color: GridTokens.hairline, width: 1),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                iconColor: GridTokens.text3,
                collapsedIconColor: GridTokens.text3,
                shape: const RoundedRectangleBorder(side: BorderSide.none),
                collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: GridTokens.mintFaint,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.devices_rounded, color: GridTokens.mint, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Device',
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: GridTokens.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          GridMono(
                            deviceId,
                            uppercase: false,
                            size: 10,
                            color: GridTokens.text3,
                            letterSpacing: 0.04,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                children: [
                  _buildKeyRow('Curve25519', keys['curve25519'] ?? 'N/A'),
                  const SizedBox(height: 8),
                  _buildKeyRow('Ed25519', keys['ed25519'] ?? 'N/A'),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildKeyRow(String keyType, String keyValue) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GridTokens.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GridTokens.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: GridTokens.mintSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: GridMono(keyType, color: GridTokens.mint, size: 9, letterSpacing: 0.1),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: keyValue));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$keyType key copied'),
                      backgroundColor: GridTokens.surface,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.copy_rounded, size: 14, color: GridTokens.mint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridMono(
            keyValue,
            uppercase: false,
            size: 10,
            color: GridTokens.text2,
            letterSpacing: 0.02,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// helpers
// ─────────────────────────────────────────────────────────────────────

/// Small mono pill (matches the "updated 12s" / "0.4 mi · NE" surface pills
/// in the design — text3 on surface2 with a hairline outline).
class _MonoPill extends StatelessWidget {
  const _MonoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: GridTokens.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GridTokens.hairline, width: 1),
      ),
      child: GridMono(label, size: 10, color: GridTokens.text2, letterSpacing: 0.08),
    );
  }
}

/// Inline copy button next to the @handle in the identity row.
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.copied, required this.onTap});

  final bool copied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(
            copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 14,
            color: copied ? GridTokens.mint : GridTokens.text3,
          ),
        ),
      ),
    );
  }
}

/// Single ShareToggle pill used inside the mutual-sharing card. Mint backing
/// when on, hairline neutral when off.
class _ShareToggle extends StatelessWidget {
  const _ShareToggle({
    required this.label,
    required this.arrow,
    required this.other,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String arrow;
  final String other;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return Opacity(
      opacity: disabled ? 0.85 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          color: value ? GridTokens.mintSoft : GridTokens.surface2,
          borderRadius: BorderRadius.circular(GridTokens.rMd),
          border: Border.all(
            color: value ? GridTokens.mint : GridTokens.hairline,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            if (value) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: GridTokens.mint,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: GridTokens.mint, blurRadius: 6, spreadRadius: 0),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$label ',
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: value ? GridTokens.mint : GridTokens.text2,
                          ),
                        ),
                        TextSpan(
                          text: arrow,
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: value ? GridTokens.mint : GridTokens.text3,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    other,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: value ? GridTokens.mint : GridTokens.text2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            _MiniSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// 30×18 mint-backed switch — compact form used inside the ShareToggle pills.
class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final track = value ? GridTokens.mint : GridTokens.surface3;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 32,
        height: 18,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the 4 action tiles in the action grid (Message / History / Route /
/// Alerts). Disabled when `onTap` is null.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Ink(
          height: 64,
          decoration: BoxDecoration(
            color: GridTokens.surface,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.hairline, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: disabled ? GridTokens.text4 : GridTokens.text,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: disabled ? GridTokens.text4 : GridTokens.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faint grid lines for the map hero placeholder.
class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GridTokens.mapRoad.withAlpha(64)
      ..strokeWidth = 1;
    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Downward-pointing pin tail under the focused-contact avatar.
class _PinTailPainter extends CustomPainter {
  _PinTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PinTailPainter old) => old.color != color;
}
