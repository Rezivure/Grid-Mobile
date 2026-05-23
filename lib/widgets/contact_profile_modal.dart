import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/services/user_device_status_cache.dart';
import 'package:grid_frontend/utilities/time_ago_formatter.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';
import 'package:grid_frontend/blocs/contacts/contacts_state.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/add_sharing_preferences_modal.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_status_pill.dart';
import 'package:grid_frontend/widgets/user_avatar_bloc.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utilities/lat_lng_validation.dart';

import '../screens/map/grid_map_style.dart';

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

  /// True when the modal was opened by tapping the contact's marker on
  /// the map. In that case:
  ///   1. The internal map hero is suppressed — the real map sits
  ///      directly behind the sheet and fades into it.
  ///   2. Speed / motion / battery are pulled from
  ///      UserDeviceStatusCache and shown inline with the identity
  ///      row, since the user_info_bubble that used to surface them is
  ///      being retired in favor of this consolidated screen.
  final bool fromMapTap;

  /// Provided by `DraggableScrollableSheet` when rendered inline by
  /// MapTab. Threaded into the SingleChildScrollView so swipe-down on
  /// the drag handle dismisses the sheet correctly.
  final ScrollController? scrollController;

  /// Called when the close button is tapped or the sheet is dismissed.
  /// MapTab uses this to clear the controller + trigger
  /// MapCameraSignals.requestReset.
  final VoidCallback? onClose;

  const ContactProfileModal({
    Key? key,
    required this.contact,
    required this.roomService,
    required this.sharingPreferencesRepo,
    this.fromMapTap = false,
    this.scrollController,
    this.onClose,
  }) : super(key: key);

  @override
  _ContactProfileModalState createState() => _ContactProfileModalState();
}

class _ContactProfileModalState extends State<ContactProfileModal> {
  bool _copied = false;
  bool _isLoading = true;
  bool _activeSharing = false;

  /// All device keys (fetched from the RoomService)
  late Map<String, Map<String, String>> _allOtherDeviceKeys;

  /// List of sharing windows loaded from the DB
  List<SharingWindow> _sharingWindows = [];

  /// Whether the device keys section is expanded
  bool _isDeviceKeysExpanded = false;

  // Relationship snapshot, computed once on modal open.
  bool _hasDirect = false;
  bool _directPending = false;
  List<_SharedGroupRef> _sharedGroups = const [];
  bool _sendingFriendRequest = false;
  StreamSubscription<ContactsState>? _contactsSub;

  @override
  void initState() {
    super.initState();
    _loadDeviceKeys();
    _computeRelationship();
    _subscribeToContacts();
  }

  @override
  void dispose() {
    _contactsSub?.cancel();
    super.dispose();
  }

  void _computeRelationship() {
    final myId = widget.roomService.getMyUserId();
    final targetId = widget.contact.userId;
    bool direct = false;
    bool pending = false;
    try {
      for (final r in widget.roomService.client.rooms) {
        final name = r.name;
        if (name == 'Grid:Direct:$myId:$targetId' ||
            name == 'Grid:Direct:$targetId:$myId') {
          direct = true;
          // Sync state lookup — cheap, no network round-trip.
          try {
            final memberEvent = r.getState('m.room.member', targetId);
            final m = memberEvent?.content['membership'] as String?;
            pending = (m == 'invite');
          } catch (_) {}
          break;
        }
      }
    } catch (_) {}

    List<_SharedGroupRef> shared = const [];
    try {
      final state = context.read<GroupsBloc>().state;
      if (state is GroupsLoaded) {
        shared = state.groups
            .where((g) => g.members.contains(targetId))
            .map((g) => _SharedGroupRef(g.roomId, utils.formatGroupName(g.name)))
            .toList();
      }
    } catch (_) {}

    _hasDirect = direct;
    _directPending = pending;
    _sharedGroups = shared;
  }

  void _subscribeToContacts() {
    try {
      final bloc = context.read<ContactsBloc>();
      _maybeFlipPendingFromContacts(bloc.state);
      _contactsSub = bloc.stream.listen(_maybeFlipPendingFromContacts);
    } catch (_) {}
  }

  void _maybeFlipPendingFromContacts(ContactsState state) {
    if (!_directPending) return;
    if (state is! ContactsLoaded) return;
    final targetId = widget.contact.userId;
    for (final c in state.contacts) {
      if (c.userId == targetId && c.membershipStatus == 'join') {
        if (mounted) setState(() => _directPending = false);
        return;
      }
    }
  }

  _RelationshipState get _relationship {
    if (_hasDirect && _sharedGroups.isNotEmpty) return _RelationshipState.both;
    if (_hasDirect) return _RelationshipState.directOnly;
    if (_sharedGroups.isNotEmpty) return _RelationshipState.groupOnly;
    return _RelationshipState.directOnly;
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
        _activeSharing = prefs?.activeSharing ?? true;
        _sharingWindows = prefs?.shareWindows ?? [];
      });
    } catch (e) {
      print('Error loading sharing preferences: $e');
      setState(() {
        _activeSharing = true; // default for new contacts
        _sharingWindows = [];
      });
    }
  }

  Future<void> _saveToDatabase() async {
    final preferences = SharingPreferences(
      targetId: widget.contact.userId,
      targetType: 'user', // Use 'user' to match what sync_manager creates
      activeSharing: _activeSharing,
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
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.gridColors.surface,
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

  void _openAddSharingPreferenceModal({SharingWindow? existing, int? index}) {
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
                days: _daysToIntList(selectedDays),
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
              final prevList = List<SharingWindow>.from(_sharingWindows);
              setState(() {
                if (isEdit) {
                  _sharingWindows[index] = next;
                } else {
                  _sharingWindows.add(next);
                }
              });
              try {
                await _saveToDatabase();
                if (!mounted) return;
                InAppNotifier.instance.show(
                  title: isEdit
                      ? 'Sharing window updated'
                      : 'Sharing window added',
                  message: isEdit
                      ? 'Changes saved.'
                      : 'Friend will see your location during this window.',
                  variant: InAppNotificationVariant.success,
                );
              } catch (e) {
                if (!mounted) return;
                setState(() => _sharingWindows = prevList);
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

  Future<void> _toggleWindowActive(int index, bool v) async {
    final prev = _sharingWindows[index];
    final updated = SharingWindow(
      label: prev.label,
      days: prev.days,
      isAllDay: prev.isAllDay,
      startTime: prev.startTime,
      endTime: prev.endTime,
      isActive: v,
    );
    setState(() => _sharingWindows[index] = updated);
    try {
      await _saveToDatabase();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sharingWindows[index] = prev);
      InAppNotifier.instance.show(
        title: 'Could not update window',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  Future<void> _deleteWindow(int index) async {
    final removed = _sharingWindows[index];
    setState(() => _sharingWindows.removeAt(index));
    try {
      await _saveToDatabase();
      if (!mounted) return;
      InAppNotifier.instance.show(
        title: 'Sharing window removed',
        message: 'You can add a new window any time.',
        variant: InAppNotificationVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sharingWindows.insert(index, removed));
      InAppNotifier.instance.show(
        title: 'Could not delete window',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  Future<void> _toggleMutualSharing(bool v, String firstName) async {
    final prev = _activeSharing;
    setState(() => _activeSharing = v);
    try {
      await _saveToDatabase();
      if (!mounted) return;
      final hasWindows = _sharingWindows.any((w) => w.isActive == true);
      InAppNotifier.instance.show(
        title: v
            ? 'Sharing resumed for $firstName'
            : 'Sharing paused for $firstName',
        message: v
            ? (hasWindows
                ? "They'll see updates during your active windows."
                : "They'll see your location continuously.")
            : 'Resume any time from this sheet.',
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

  List<int> _daysToIntList(List<bool> selectedDays) {
    final days = <int>[];
    for (int i = 0; i < selectedDays.length; i++) {
      if (selectedDays[i]) days.add(i);
    }
    return days;
  }

  // Viewer-facing freshness only; never expose the friend's paused/incognito.
  GridAvatarStatus _contactStatus(BuildContext context) {
    final loc = context
        .watch<UserLocationProvider>()
        .getUserLocation(widget.contact.userId);
    if (loc == null) return GridAvatarStatus.idle;
    DateTime? ts;
    try {
      ts = DateTime.parse(loc.timestamp).toLocal();
    } catch (_) {
      return GridAvatarStatus.idle;
    }
    return statusFromLastUpdate(ts);
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

    final inline = widget.fromMapTap;

    // ClipRRect gives a real rounded top edge — the previous straight
    // hard cut is replaced by a softly curved corner that reads as
    // "the map dives behind this sheet" rather than a guillotine.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
          top: Radius.circular(GridTokens.r2Xl)),
      child: Stack(
        children: [
          // Solid sheet body — `surface` matches the Grid 2.0 sheets
          // sitting on `bg`. Buttons inside use `surface2` for
          // hierarchy.
          Positioned.fill(
            child: ColoredBox(color: context.gridColors.surface),
          ),

          // Scrollable content.
          SingleChildScrollView(
            controller: widget.scrollController,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (inline) ...[
                  // Tight top spacer so the name row sits below the
                  // rounded corner without the avatar getting clipped.
                  // No drag handle (user asked for it gone) and no
                  // fake-map hero — the real map is right above us.
                  const SizedBox(height: 18),
                ] else ...[
                  // Drag handle for list-entry presentation only.
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.gridColors.text4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // 280pt fake-map hero with the focused pin — shown
                  // when invoked from a contact list entry point
                  // where we don't already have the live map behind.
                  _buildMapHero(),
                ],

                Transform.translate(
                  offset: inline ? Offset.zero : const Offset(0, -32),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: _buildIdentityRow(
                        userLocalpart, handle, showFullMatrixId),
                  ),
                ),

                Transform.translate(
                  offset: inline ? Offset.zero : const Offset(0, -32),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 14),
                        _buildStatusRow(),
                        const SizedBox(height: 18),
                        ..._buildRelationshipBlock(firstName),
                        const SizedBox(height: 14),
                        _buildActionGrid(),
                        const SizedBox(height: 22),
                        _buildSharedGroups(),
                        if (_relationship != _RelationshipState.groupOnly &&
                            !_directPending) ...[
                          const SizedBox(height: 22),
                          _buildSectionLabel('SHARING WINDOWS'),
                          const SizedBox(height: 10),
                          _buildSharingWindows(),
                        ],
                        const SizedBox(height: 22),
                        _buildSectionLabel('SECURITY'),
                        const SizedBox(height: 10),
                        _buildSecurityCard(),
                        if (_hasDirect) ...[
                          const SizedBox(height: 22),
                          _buildRemoveContactButton(),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Floating close X — clearly visible and easy to tap.
          // Sits in the top-right with safe distance from the
          // rounded corner. Only rendered when an onClose callback
          // is provided (inline-from-map flow).
          if (widget.onClose != null)
            Positioned(
              top: 14,
              right: 14,
              child: _FloatingCloseButton(onTap: widget.onClose!),
            ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // hero
  // ────────────────────────────────────────────────────────────────────

  Widget _buildMapHero() {
    // If we have an actual location for this contact, embed a tiny
    // non-interactive MapLibre map centered on them. Otherwise fall back
    // to the stylized dark surface + grid (which used to be the only
    // thing rendered here).
    final position =
        Provider.of<UserLocationProvider>(context, listen: false)
            .getUserLocation(widget.contact.userId);
    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          if (position != null)
            Positioned.fill(child: _MapSnapshot(position: position))
          else
            Positioned.fill(
              child: Stack(
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [GridTokens.mapBg, GridTokens.mapLand],
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: _MapGridPainter(),
                    size: Size.infinite,
                  ),
                ],
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
                    context.gridColors.bg.withAlpha(0),
                    context.gridColors.bg,
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
    final status = _contactStatus(context);
    final live = status == GridAvatarStatus.live;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Floating label chip above the pin
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: context.gridColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.gridColors.hairlineStrong, width: 1),
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
                  color: context.gridColors.text,
                ),
              ),
              const SizedBox(width: 6),
              GridMono(
                widget.contact.lastSeen.isEmpty ? 'now' : widget.contact.lastSeen,
                size: 9,
                color: context.gridColors.text3,
                letterSpacing: 0.06,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Pin: ringed avatar with downward tail. Uses UserAvatarBloc so
        // the contact's real photo (if any) shows up here too.
        SizedBox(
          width: 64,
          height: 80,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              GridAvatar(
                name: widget.contact.displayName,
                userId: widget.contact.userId,
                size: 48,
                ring: true,
                status: status,
              ),
              Positioned(
                bottom: 6,
                child: CustomPaint(
                  size: const Size(14, 10),
                  painter: _PinTailPainter(
                    color: live ? context.gridColors.mint : context.gridColors.hairlineStrong,
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
    final status = _contactStatus(context);
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.gridColors.bg,
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
                          color: context.gridColors.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (status == GridAvatarStatus.live) ...[
                      const SizedBox(width: 8),
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: GridLiveBadge(),
                      ),
                    ],
                    // Reserve enough trailing space for the floating
                    // close X so the name doesn't run into it.
                    if (widget.onClose != null) const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: GridMono(
                        handle.startsWith('@') ? handle : '@$handle',
                        uppercase: false,
                        size: 12,
                        color: context.gridColors.text3,
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
    // Concrete relative time ("LAST 3H AGO") instead of "UPDATED OFFLINE",
    // which read like an oxymoron. "NEVER" when we truly have no fix.
    final loc = Provider.of<UserLocationProvider>(context, listen: false)
        .getUserLocation(widget.contact.userId);
    final updatedLabel = _formatFreshness(loc?.timestamp);

    // gridv 2: pull live device-status (motion / speed / battery) from
    // the cache for the contact (not the local user). Subscribe so the
    // row rebuilds as fresh fixes land while the sheet is open.
    final status =
        context.watch<UserDeviceStatusCache>().statusFor(widget.contact.userId);
    final motionLabel = _formatMotion(status?.speed);
    final speedLabel = _formatSpeed(status?.speed);

    // SHARING/PAUSED pill removed — it was bound to the local user's
    // outgoing toggle, duplicating the mutual-sharing card below.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MotionStatusPill(motion: motionLabel, speed: speedLabel),
        _BatteryStatusPill(
          level: status?.batteryLevel,
          charging: status?.isCharging ?? false,
        ),
        _MonoPill(label: updatedLabel),
      ],
    );
  }

  String _formatFreshness(String? timestamp) {
    if (timestamp == null) return 'NEVER';
    final ago = TimeAgoFormatter.format(timestamp);
    if (ago == 'Offline') return 'NEVER';
    if (ago == 'Just now') return 'LAST JUST NOW';
    final stripped = ago.endsWith(' ago')
        ? ago.substring(0, ago.length - 4)
        : ago;
    return 'LAST ${stripped.toUpperCase()} AGO';
  }

  // Same banding as the old user_info_bubble.
  String? _formatMotion(double? speedMps) {
    if (speedMps == null || speedMps < 1.4) return null;
    if (speedMps < 5) return 'WALKING';
    return 'DRIVING';
  }

  String? _formatSpeed(double? speedMps) {
    if (speedMps == null || speedMps < 1.4) return null;
    return '${(speedMps * 2.236936).round()} mph';
  }

  // ────────────────────────────────────────────────────────────────────
  // mutual sharing card
  // ────────────────────────────────────────────────────────────────────

  Widget _buildMutualSharingCard(String firstName) {
    final hasActiveWindows =
        _sharingWindows.any((w) => w.isActive == true);
    // 3 states: on (always), scheduled (off + active windows), paused (off + no windows)
    final bool scheduled = !_activeSharing && hasActiveWindows;
    final bool paused = !_activeSharing && !hasActiveWindows;

    final String title;
    final String subtitle;
    final IconData iconData;
    if (_activeSharing) {
      title = 'Sharing with $firstName';
      subtitle = 'End-to-end encrypted. Toggle off any time.';
      iconData = Icons.shield_outlined;
    } else if (scheduled) {
      title = 'Scheduled with $firstName';
      subtitle = 'They see your location during active windows.';
      iconData = Icons.schedule_rounded;
    } else {
      title = 'Paused with $firstName';
      subtitle = "$firstName won't see your location until you resume.";
      iconData = Icons.pause_circle_outline_rounded;
    }

    // Paused (no windows) gets a neutral surface; scheduled & active keep mint.
    final Color bgColor = paused
        ? context.gridColors.surface2
        : context.gridColors.mintFaint;
    final Color borderColor = paused
        ? context.gridColors.hairline
        : context.gridColors.mintSoft;
    final Color iconBgColor = paused
        ? context.gridColors.surface
        : context.gridColors.mintSoft;
    final Color iconColor = paused
        ? context.gridColors.text3
        : context.gridColors.mint;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              iconData,
              size: 18,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 12),
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
                    letterSpacing: -0.005,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch.adaptive(
            value: _activeSharing,
            activeColor: context.gridColors.mint,
            onChanged: (value) => _toggleMutualSharing(value, firstName),
          ),
        ],
      ),
    );
  }

  // Branches the slot that normally holds the "Sharing with X" card by
  // relationship state.
  List<Widget> _buildRelationshipBlock(String firstName) {
    if (_directPending) {
      return [
        _buildPendingRequestRow(firstName),
        if (_sharedGroups.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildGroupOnlyCaption(),
        ],
      ];
    }
    if (_relationship == _RelationshipState.groupOnly) {
      return [
        _buildFriendRequestButton(firstName),
      ];
    }
    final showWarning =
        _relationship == _RelationshipState.both && !_activeSharing;
    return [
      _buildMutualSharingCard(firstName),
      if (showWarning) ...[
        const SizedBox(height: 8),
        _buildGroupVisibilityWarning(),
      ],
    ];
  }

  Widget _buildFriendRequestButton(String firstName) {
    return GridButton(
      label: _sendingFriendRequest
          ? 'Sending…'
          : 'Send friend request',
      icon: Icons.person_add_alt_1_rounded,
      style: GridButtonStyle.secondary,
      onPressed: _sendingFriendRequest ? null : _sendFriendRequest,
    );
  }

  // Informational inline pill shown after a friend request is sent but
  // before the target accepts. Mirrors the "scheduled" mintFaint chrome
  // from _buildMutualSharingCard so it reads as a status, not a button.
  Widget _buildPendingRequestRow(String firstName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.gridColors.mintFaint,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: context.gridColors.mintSoft, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.gridColors.mintSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.schedule_send_rounded,
              size: 16,
              color: context.gridColors.mint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Friend request sent — waiting for $firstName to accept',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.gridColors.text2,
                height: 1.35,
                letterSpacing: -0.005,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupOnlyCaption() {
    final text = _sharedGroups.length == 1
        ? 'You share with them through ${_sharedGroups.first.name}'
        : 'You share with them through ${_sharedGroups.length} groups';
    return Text(
      text,
      style: GoogleFonts.getFont(
        'Geist',
        fontSize: 12.5,
        color: context.gridColors.text3,
        height: 1.35,
        letterSpacing: -0.005,
      ),
    );
  }

  Widget _buildGroupVisibilityWarning() {
    final label = _sharedGroups.length == 1
        ? 'Direct sharing off — still visible via ${_sharedGroups.first.name}'
        : 'Direct sharing off — still visible via ${_sharedGroups.length} shared groups';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.gridColors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: context.gridColors.amber.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14, color: context.gridColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 12,
                color: context.gridColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFriendRequest() async {
    final firstName = widget.contact.displayName.split(' ').first;
    setState(() => _sendingFriendRequest = true);
    InAppNotifier.instance.show(
      title: 'Friend request sent',
      message: 'They will see it shortly.',
      variant: InAppNotificationVariant.success,
    );
    try {
      final ok = await widget.roomService
          .createRoomAndInviteContact(widget.contact.userId);
      if (!mounted) return;
      if (!ok) {
        InAppNotifier.instance.show(
          title: 'Could not send request',
          message: 'Already friends or request pending with $firstName.',
          variant: InAppNotificationVariant.warning,
        );
        setState(() => _sendingFriendRequest = false);
        return;
      }
      // Wire up the new direct room into ContactsBloc, matching add_friend_modal.
      final myUserId = widget.roomService.getMyUserId();
      if (myUserId != null) {
        try {
          final rooms = widget.roomService.client.rooms;
          final directRoom = rooms.where((room) {
            final name = room.name;
            return name == 'Grid:Direct:$myUserId:${widget.contact.userId}' ||
                name == 'Grid:Direct:${widget.contact.userId}:$myUserId';
          }).firstOrNull;
          if (directRoom != null && mounted) {
            await context
                .read<ContactsBloc>()
                .handleNewContactInvited(directRoom.id, widget.contact.userId);
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _hasDirect = true;
        _directPending = true;
        _sendingFriendRequest = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingFriendRequest = false);
      InAppNotifier.instance.show(
        title: 'Friend request failed',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // 4-button action grid
  // ────────────────────────────────────────────────────────────────────

  Widget _buildActionGrid() {
    // Stripped to the two actions the app actually supports today.
    // Message + History are intentionally absent — Grid doesn't keep a
    // per-contact message thread or location history yet, so showing
    // them as disabled tiles was just teasing functionality that
    // doesn't exist.
    final position =
        Provider.of<UserLocationProvider>(context, listen: false)
            .getUserLocation(widget.contact.userId);
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.alt_route_rounded,
            label: 'Route',
            onTap: position == null
                ? null
                : () => _openInMaps(
                      lat: position.latitude,
                      lng: position.longitude,
                    ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSharingActionTile(),
        ),
      ],
    );
  }

  Widget _buildSharingActionTile() {
    final managedInGroup = _relationship == _RelationshipState.groupOnly ||
        _directPending;
    if (managedInGroup) {
      final subtext = _sharedGroups.length <= 1
          ? 'Managed in group'
          : 'Managed in groups';
      return _ActionTile(
        icon: Icons.schedule_rounded,
        label: 'Sharing',
        subtext: subtext,
        mutedAmber: true,
        onTap: null,
      );
    }
    return _ActionTile(
      icon: Icons.schedule_rounded,
      label: 'Sharing',
      onTap: _openAddSharingPreferenceModal,
    );
  }

  Future<void> _openInMaps({
    required double lat,
    required double lng,
  }) async {
    final iosUri = Uri.parse('maps://?q=$lat,$lng');
    final fallbackUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (Platform.isIOS) {
        if (await canLaunchUrl(iosUri)) {
          await launchUrl(iosUri);
          return;
        }
      }
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ────────────────────────────────────────────────────────────────────
  // shared groups
  // ────────────────────────────────────────────────────────────────────

  Widget _buildSharedGroups() {
    final groups = _sharedGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('SHARED GROUPS'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: context.gridColors.surface,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: context.gridColors.hairline, width: 1),
          ),
          child: groups.isEmpty
              ? Row(
                  children: [
                    Icon(Icons.groups_2_outlined,
                        size: 18, color: context.gridColors.text3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No shared groups yet',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: context.gridColors.text2,
                        ),
                      ),
                    ),
                  ],
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in groups)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.gridColors.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: context.gridColors.hairline, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.groups_2_outlined,
                                size: 12, color: context.gridColors.text3),
                            const SizedBox(width: 6),
                            Text(
                              g.name,
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: context.gridColors.text2,
                              ),
                            ),
                          ],
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
          child: GridMono(text, size: 10, color: context.gridColors.text3, letterSpacing: 0.12),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // sharing windows (kept for when _activeSharing is off)
  // ────────────────────────────────────────────────────────────────────

  Widget _buildSharingWindows() {
    // When _activeSharing is true the backend ignores windows entirely
    // (see UserService.isInSharingWindow). Show the rows so the user
    // can still curate them, but visually flag the override.
    final scheduleSuperseded = _activeSharing;

    if (_sharingWindows.isEmpty) {
      final emptyCopy = _activeSharing
          ? 'No sharing windows yet. Add one to share on a schedule.'
          : 'Sharing is paused. Add a window to share on a schedule, or turn sharing back on for continuous updates.';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scheduleSuperseded) _buildScheduleSupersededNote(),
          if (scheduleSuperseded) const SizedBox(height: 10),
          Text(
            emptyCopy,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              color: context.gridColors.text2,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: _buildAddWindowChip(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scheduleSuperseded) _buildScheduleSupersededNote(),
        if (scheduleSuperseded) const SizedBox(height: 10),
        if (!_activeSharing) _buildScheduledModeNote(),
        if (!_activeSharing) const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: context.gridColors.surface,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: context.gridColors.hairline),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _sharingWindows.length; i++) ...[
                _buildSharingWindowRow(_sharingWindows[i], i),
                if (i < _sharingWindows.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: context.gridColors.hairline,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: _buildAddWindowChip(),
        ),
      ],
    );
  }

  Widget _buildScheduleSupersededNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.gridColors.surface2,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: context.gridColors.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.all_inclusive_rounded,
              size: 14, color: context.gridColors.text3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sharing 24/7 — schedule paused',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 12,
                color: context.gridColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduledModeNote() {
    final hasActive = _sharingWindows.any((w) => w.isActive == true);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.gridColors.mintFaint,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: context.gridColors.mintSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded,
              size: 14, color: context.gridColors.mint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasActive
                  ? 'Schedule active — sharing during your windows'
                  : 'All windows off — no scheduled sharing',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 12,
                color: context.gridColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddWindowChip() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openAddSharingPreferenceModal(),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.gridColors.mintSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 14, color: context.gridColors.mint),
              const SizedBox(width: 6),
              Text(
                'Add window',
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.gridColors.mint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSharingWindowRow(SharingWindow window, int index) {
    final summary = _summariseWindow(window);
    // Dim when always-share supersedes the schedule, or when the
    // window itself is paused. Per-row switch still works in both
    // states; trash always works.
    final dim = _activeSharing || !window.isActive;
    final rowSwitchEnabled = !_activeSharing;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openAddSharingPreferenceModal(
          existing: window,
          index: index,
        ),
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
                onChanged: rowSwitchEnabled
                    ? (v) => _toggleWindowActive(index, v)
                    : null,
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: context.gridColors.text3,
                ),
                tooltip: 'Delete window',
                visualDensity: VisualDensity.compact,
                onPressed: () => _deleteWindow(index),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _summariseWindow(SharingWindow window) {
    const dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = [...window.days]..sort();
    String daysPart;
    if (sorted.isEmpty) {
      daysPart = 'No days';
    } else if (sorted.length == 7) {
      daysPart = 'Every day';
    } else if (sorted.length == 5 &&
        sorted.every((d) => d >= 0 && d <= 4)) {
      daysPart = 'Workdays';
    } else if (sorted.length == 2 && sorted[0] == 5 && sorted[1] == 6) {
      daysPart = 'Weekends';
    } else {
      daysPart = sorted.map((d) => dayShort[d]).join(', ');
    }
    final timePart = window.isAllDay
        ? 'All day'
        : '${_fmtClock(window.startTime)} – ${_fmtClock(window.endTime)}';
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

  // ────────────────────────────────────────────────────────────────────
  // security (device keys) — kept, but restyled
  // ────────────────────────────────────────────────────────────────────

  /// Destructive bottom action — replaces the long-press 'Remove
  /// contact' menu that we just deleted from contacts_subscreen. Lives
  /// inside the profile sheet so contact management is all on one
  /// screen.
  Widget _buildRemoveContactButton() {
    return GridButton(
      label: 'Remove contact',
      icon: Icons.delete_outline_rounded,
      style: GridButtonStyle.danger,
      onPressed: _confirmAndRemoveContact,
    );
  }

  Future<void> _confirmAndRemoveContact() async {
    final firstName = widget.contact.displayName.split(' ').first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            decoration: BoxDecoration(
              color: context.gridColors.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: context.gridColors.hairline),
            ),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: context.gridColors.dangerSoft,
                        borderRadius: BorderRadius.circular(GridTokens.rSm),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: context.gridColors.danger,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Remove $firstName?',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.015,
                          color: context.gridColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '$firstName will be removed from your contacts. '
                  "You'll stop sharing location with each other.",
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 13,
                    color: context.gridColors.text2,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: GridButton(
                        label: 'Cancel',
                        style: GridButtonStyle.secondary,
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GridButton(
                        label: 'Remove',
                        style: GridButtonStyle.danger,
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      context.read<ContactsBloc>().add(DeleteContact(widget.contact.userId));
    } catch (_) {}
    InAppNotifier.instance.show(
      title: 'Removing $firstName',
      message: 'Removing from contacts…',
      variant: InAppNotificationVariant.info,
    );
    if (!mounted) return;
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _buildSecurityCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.gridColors.surface,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: context.gridColors.hairline, width: 1),
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
                        color: context.gridColors.mintFaint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.shield_outlined, size: 18, color: context.gridColors.mint),
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
                              color: context.gridColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Verify your contact\'s identity',
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: context.gridColors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isDeviceKeysExpanded ? Icons.expand_less : Icons.expand_more,
                      color: context.gridColors.text3,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isDeviceKeysExpanded) ...[
            Divider(height: 1, color: context.gridColors.hairline),
            Padding(
              padding: const EdgeInsets.all(14),
              child: _isLoading
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: context.gridColors.mint),
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
          color: context.gridColors.surface2,
          borderRadius: BorderRadius.circular(GridTokens.rMd),
        ),
        child: Column(
          children: [
            Icon(Icons.shield_outlined, size: 36, color: context.gridColors.text3),
            const SizedBox(height: 10),
            Text(
              'No security keys yet',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.gridColors.text2,
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
                color: context.gridColors.text3,
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
            color: context.gridColors.mintFaint,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: context.gridColors.mintSoft, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: context.gridColors.mint, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Compare these keys with the ones in your contact's settings.",
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: context.gridColors.mint,
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
              color: context.gridColors.surface2,
              borderRadius: BorderRadius.circular(GridTokens.rMd),
              border: Border.all(color: context.gridColors.hairline, width: 1),
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
                iconColor: context.gridColors.text3,
                collapsedIconColor: context.gridColors.text3,
                shape: const RoundedRectangleBorder(side: BorderSide.none),
                collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: context.gridColors.mintFaint,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.devices_rounded, color: context.gridColors.mint, size: 16),
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
                              color: context.gridColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          GridMono(
                            deviceId,
                            uppercase: false,
                            size: 10,
                            color: context.gridColors.text3,
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
        color: context.gridColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.gridColors.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.gridColors.mintSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: GridMono(keyType, color: context.gridColors.mint, size: 9, letterSpacing: 0.1),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: keyValue));
                  InAppNotifier.instance.show(
                    title: '$keyType key copied',
                    message: 'Compare it against the contact to verify.',
                    variant: InAppNotificationVariant.success,
                    duration: const Duration(seconds: 2),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.copy_rounded, size: 14, color: context.gridColors.mint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridMono(
            keyValue,
            uppercase: false,
            size: 10,
            color: context.gridColors.text2,
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

enum _RelationshipState { directOnly, groupOnly, both }

class _SharedGroupRef {
  final String roomId;
  final String name;
  const _SharedGroupRef(this.roomId, this.name);
}

/// Mint pill showing DRIVING / WALKING / STILL + mph next to it.
/// Falls back to a muted STILL pill when speed is unknown / sub-walking
/// so the slot is always visible. Distinct from freshness "idle".
class _MotionStatusPill extends StatelessWidget {
  const _MotionStatusPill({required this.motion, this.speed});

  final String? motion;
  final String? speed;

  @override
  Widget build(BuildContext context) {
    final muted = motion == null;
    final color = muted ? context.gridColors.text3 : context.gridColors.mint;
    final bg = muted ? context.gridColors.surface2 : context.gridColors.mintFaint;
    final border = muted ? context.gridColors.hairline : context.gridColors.mintSoft;
    final IconData icon;
    if (motion == 'DRIVING') {
      icon = Icons.directions_car_filled_rounded;
    } else if (motion == 'WALKING') {
      icon = Icons.directions_walk_rounded;
    } else {
      icon = Icons.do_not_disturb_on_total_silence_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          GridMono(motion ?? 'STILL',
              size: 10, color: color, letterSpacing: 0.08),
          if (speed != null) ...[
            const SizedBox(width: 5),
            GridMono(speed!,
                uppercase: false,
                size: 10,
                color: color,
                letterSpacing: 0.02),
          ],
        ],
      ),
    );
  }
}

/// Battery pill — same banding as the user_info_bubble glyph (danger
/// red < 20 %, amber < 40 %, mint when charging, text2 otherwise).
/// Grey "?" placeholder when the sender hasn't shipped gridv 2 yet.
class _BatteryStatusPill extends StatelessWidget {
  const _BatteryStatusPill({required this.level, required this.charging});

  final double? level;
  final bool charging;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String label;
    if (level == null) {
      color = context.gridColors.text3;
      icon = Icons.battery_unknown_rounded;
      label = '?';
    } else if (charging) {
      color = context.gridColors.mint;
      icon = Icons.bolt_rounded;
      label = '${(level! * 100).round()}%';
    } else if (level! < 0.20) {
      color = context.gridColors.danger;
      icon = Icons.battery_alert_rounded;
      label = '${(level! * 100).round()}%';
    } else if (level! < 0.40) {
      color = context.gridColors.amber;
      icon = Icons.battery_3_bar_rounded;
      label = '${(level! * 100).round()}%';
    } else {
      color = context.gridColors.text2;
      icon = Icons.battery_5_bar_rounded;
      label = '${(level! * 100).round()}%';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          GridMono(label,
              uppercase: false,
              size: 10,
              color: color,
              letterSpacing: 0.06),
        ],
      ),
    );
  }
}

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
        color: context.gridColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.gridColors.hairline, width: 1),
      ),
      child: GridMono(label, size: 10, color: context.gridColors.text2, letterSpacing: 0.08),
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
            color: copied ? context.gridColors.mint : context.gridColors.text3,
          ),
        ),
      ),
    );
  }
}

/// Prominent floating X close button. Sits in the top-right of the
/// inline profile sheet on top of the rounded corner so it reads as a
/// distinct affordance, not a tucked-away link. 44pt tap target with
/// a subtle hairline border so it's visible against both the sheet
/// surface and the map underneath when scrolled.
class _FloatingCloseButton extends StatelessWidget {
  const _FloatingCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.gridColors.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: context.gridColors.hairlineStrong, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.close_rounded,
            size: 20,
            color: context.gridColors.text,
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtext,
    this.mutedAmber = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? subtext;
  final bool mutedAmber;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final colors = context.gridColors;
    final bgColor = mutedAmber ? colors.amberSoft : colors.surface2;
    final borderColor = mutedAmber ? colors.amber.withOpacity(0.45) : colors.hairline;
    final iconColor = mutedAmber
        ? colors.amber
        : (disabled ? colors.text4 : colors.text);
    final labelColor = mutedAmber
        ? colors.text2
        : (disabled ? colors.text4 : colors.text2);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Ink(
          height: 64,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                ),
              ),
              if (subtext != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtext!,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: mutedAmber ? colors.amber : colors.text3,
                    letterSpacing: -0.005,
                  ),
                ),
              ],
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

/// Non-interactive MapLibre snapshot used as the hero background of the
/// contact profile sheet. Uses the same Protomaps style as the main map
/// so the dark / light theming matches.
class _MapSnapshot extends StatefulWidget {
  const _MapSnapshot({required this.position});
  final dynamic position;

  @override
  State<_MapSnapshot> createState() => _MapSnapshotState();
}

class _MapSnapshotState extends State<_MapSnapshot> {
  String? _styleJson;
  bool? _isDark;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isDark != isDark) {
      _isDark = isDark;
      _styleJson = buildGridMapStyle(dark: isDark);
    }
    final pos = widget.position;
    final safeLat = isFiniteLatLng(pos.latitude, pos.longitude) ? pos.latitude : 0.0;
    final safeLng = isFiniteLatLng(pos.latitude, pos.longitude) ? pos.longitude : 0.0;
    return IgnorePointer(
      child: ml.MapLibreMap(
        styleString: _styleJson!,
        initialCameraPosition: ml.CameraPosition(
          target: ml.LatLng(safeLat, safeLng),
          zoom: 14,
        ),
        myLocationEnabled: false,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        zoomGesturesEnabled: false,
        scrollGesturesEnabled: false,
        compassEnabled: false,
        attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
      ),
    );
  }
}
