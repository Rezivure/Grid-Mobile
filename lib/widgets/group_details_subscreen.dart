import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/models/room.dart' as GridRoom;
import 'package:grid_frontend/models/grid_user.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/services/contact_sheet_controller.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/widgets/group_markers_modal.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_contact_row.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_segmented.dart';
import 'package:grid_frontend/widgets/grid/grid_sheet.dart';
import 'package:grid_frontend/widgets/grid/grid_status_pill.dart';

import '../blocs/groups/groups_event.dart';
import '../blocs/groups/groups_state.dart';
import '../services/user_service.dart';
import '../utilities/time_ago_formatter.dart';
import 'add_group_member_modal.dart';
import 'group_sharing_windows_modal.dart';
import 'location_history_modal.dart';
import 'manage_members_modal.dart';

class GroupDetailsSubscreen extends StatefulWidget {
  final UserService userService;
  final RoomService roomService;
  final UserRepository userRepository;
  final SharingPreferencesRepository sharingPreferencesRepository;
  final ScrollController scrollController;
  final GridRoom.Room room;
  final VoidCallback onGroupLeft;

  const GroupDetailsSubscreen({
    Key? key,
    required this.scrollController,
    required this.room,
    required this.onGroupLeft,
    required this.roomService,
    required this.userRepository,
    required this.sharingPreferencesRepository,
    required this.userService,
  }) : super(key: key);

  @override
  _GroupDetailsSubscreenState createState() => _GroupDetailsSubscreenState();
}

class _GroupDetailsSubscreenState extends State<GroupDetailsSubscreen>
    with TickerProviderStateMixin {
  bool _isLeaving = false;

  final TextEditingController _searchController = TextEditingController();
  List<GridUser> _filteredMembers = [];
  String? _currentUserId;
  Timer? _refreshTimer;
  Timer? _expiryTicker;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _searchController.addListener(_filterMembers);
    _loadCurrentUser();

    // Tick once a minute so the "ends in X" copy updates without a full reload.
    _expiryTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSubscreenSelected('group:${widget.room.roomId}');
      context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));
      _fadeController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _searchController.dispose();
    _refreshTimer?.cancel();
    _expiryTicker?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    _currentUserId = await widget.userService.getMyUserId();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshMembers();
  }

  Future<void> _refreshMembers() async {
    if (!mounted) return;
    context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));
  }

  @override
  void didUpdateWidget(GroupDetailsSubscreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.roomId != widget.room.roomId) {
      _onSubscreenSelected('group:${widget.room.roomId}');
      _refreshMembers();
    }
  }

  void _openMemberSheet(GridUser user, String timeAgoText, DateTime? lastUpdateAt) {
    if (user.userId == _currentUserId) return;
    final contact = ContactDisplay(
      userId: user.userId,
      displayName: user.displayName ?? localpart(user.userId),
      avatarUrl: user.profileStatus,
      lastSeen: timeAgoText,
      lastUpdateAt: lastUpdateAt,
    );
    context.read<MapBloc>().add(MapMoveToUser(user.userId));
    ContactSheetController.instance.open(contact);
  }

  void _showToast(String text, {required bool danger, String? subtext}) {
    InAppNotifier.instance.show(
      title: text,
      message: subtext,
      variant: danger
          ? InAppNotificationVariant.error
          : InAppNotificationVariant.success,
    );
  }

  Widget _menuRow({
    required IconData icon,
    required String label,
    required Color tint,
    required Color bgTint,
    VoidCallback? onTap,
    Color? labelColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: bgTint,
                  borderRadius: BorderRadius.circular(GridTokens.rSm),
                ),
                child: Icon(icon, color: tint, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: onTap == null
                        ? context.gridColors.text4
                        : (labelColor ??
                            (tint == context.gridColors.danger
                                ? context.gridColors.danger
                                : context.gridColors.text)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSubscreenSelected(String subscreen) {
    Provider.of<SelectedSubscreenProvider>(context, listen: false)
        .setSelectedSubscreen(subscreen);
  }

  void _filterMembers() {
    if (mounted) {
      final state = context.read<GroupsBloc>().state;
      if (state is GroupsLoaded && state.selectedRoomMembers != null) {
        final searchText = _searchController.text.toLowerCase();
        setState(() {
          _filteredMembers = state.selectedRoomMembers!
              .where((user) => user.userId != _currentUserId)
              .where((user) =>
                  (user.displayName?.toLowerCase().contains(searchText) ??
                      false) ||
                  user.userId.toLowerCase().contains(searchText))
              .toList();
        });
      }
    }
  }

  Future<void> _showLeaveConfirmationDialog() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            decoration: BoxDecoration(
              color: context.gridColors.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: context.gridColors.hairline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.gridColors.dangerSoft,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(GridTokens.rXl),
                      topRight: Radius.circular(GridTokens.rXl),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: context.gridColors.danger.withOpacity(0.18),
                          borderRadius:
                              BorderRadius.circular(GridTokens.rMd),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.exit_to_app,
                          color: context.gridColors.danger,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Leave group',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.015,
                                color: context.gridColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "This action cannot be undone.",
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: context.gridColors.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Text(
                    'Are you sure you want to leave this group?',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: context.gridColors.text2,
                      height: 1.45,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: GridButton(
                          label: 'Cancel',
                          style: GridButtonStyle.secondary,
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GridButton(
                          label: 'Leave',
                          style: GridButtonStyle.danger,
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldLeave == true) {
      await _leaveGroup();
    }
  }

  Future<void> _leaveGroup() async {
    setState(() {
      _isLeaving = true;
    });

    try {
      await widget.roomService.leaveRoom(widget.room.roomId);
      if (mounted) {
        context.read<GroupsBloc>().add(RefreshGroups());
        _showToast('You have left the group', danger: false, subtext: 'You will no longer share or see members.');
      }
      widget.onGroupLeft();
    } catch (e) {
      if (mounted) {
        _showToast('Error leaving group: $e', danger: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLeaving = false;
        });
      }
    }
  }

  void _showAddGroupMemberModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: context.gridColors.surface,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(GridTokens.r2Xl)),
        ),
        child: AddGroupMemberModal(
          roomId: widget.room.roomId,
          groupName: _groupName,
          userService: widget.userService,
          roomService: widget.roomService,
          userRepository: widget.userRepository,
          onInviteSent: () {
            context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));
          },
        ),
      ),
    );
  }

  void _openGroupSharingWindowModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: GroupSharingWindowsModal(
            roomId: widget.room.roomId,
            groupName: _groupName,
            sharingPreferencesRepository: widget.sharingPreferencesRepository,
          ),
        );
      },
    );
  }

  void _showManageMembersModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: ManageMembersModal(
            roomId: widget.room.roomId,
            roomService: widget.roomService,
          ),
        );
      },
    );
  }

  void _showGroupMarkersModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: GroupMarkersModal(
            roomId: widget.room.roomId,
            roomName: _groupName,
            mapIconRepository: MapIconRepository(DatabaseService()),
          ),
        );
      },
    );
  }

  void _showGroupDetailsMenu() {
    final matrixRoom =
        widget.roomService.client.getRoomById(widget.room.roomId);
    final canManage = matrixRoom != null &&
        (matrixRoom.canKick || matrixRoom.canChangePowerLevel);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final memberCount = _filteredMembers.length;
        return GridSheetContainer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GridSheetHeader(
                title: _groupName,
                subtitle:
                    '$memberCount member${memberCount == 1 ? '' : 's'}',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _menuRow(
                      icon: Icons.person_add_outlined,
                      label: 'Add member',
                      tint: context.gridColors.mint,
                      bgTint: context.gridColors.mintFaint,
                      onTap: () {
                        Navigator.pop(context);
                        _showAddGroupMemberModal();
                      },
                    ),
                    _menuRow(
                      icon: Icons.history,
                      label: 'View history',
                      tint: context.gridColors.mint,
                      bgTint: context.gridColors.mintFaint,
                      onTap: () {
                        Navigator.pop(context);
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (BuildContext context) {
                            return ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.of(context).size.height * 0.85,
                              ),
                              child: LocationHistoryModal(
                                userId: widget.room.roomId,
                                userName: _groupName,
                                memberIds: _filteredMembers
                                    .map((m) => m.userId)
                                    .toList(),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    _menuRow(
                      icon: Icons.location_on,
                      label: 'View markers',
                      tint: context.gridColors.mint,
                      bgTint: context.gridColors.mintFaint,
                      onTap: () {
                        Navigator.pop(context);
                        _showGroupMarkersModal();
                      },
                    ),
                    _menuRow(
                      icon: Icons.schedule_rounded,
                      label: 'Sharing windows',
                      tint: context.gridColors.mint,
                      bgTint: context.gridColors.mintFaint,
                      onTap: () {
                        Navigator.pop(context);
                        _openGroupSharingWindowModal();
                      },
                    ),
                    if (canManage)
                      _menuRow(
                        icon: Icons.admin_panel_settings_outlined,
                        label: 'Manage members',
                        tint: context.gridColors.amber,
                        bgTint: context.gridColors.amberSoft,
                        labelColor: context.gridColors.amber,
                        onTap: () {
                          Navigator.pop(context);
                          _showManageMembersModal();
                        },
                      ),
                    _menuRow(
                      icon: Icons.exit_to_app_outlined,
                      label: 'Leave group',
                      tint: context.gridColors.danger,
                      bgTint: context.gridColors.dangerSoft,
                      onTap: _isLeaving
                          ? null
                          : () {
                              Navigator.pop(context);
                              _showLeaveConfirmationDialog();
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── derived helpers ────────────────────────────────────────────────

  String get _groupName {
    final parts = widget.room.name.split(':');
    return parts.length >= 5 ? parts[3] : widget.room.name;
  }

  int _liveCount(GroupsLoaded state, List<UserLocation> userLocations) {
    int live = 0;
    for (final m in _filteredMembers) {
      if (state.getMemberStatus(m.userId) == 'invite') continue;
      final loc = userLocations
          .cast<UserLocation?>()
          .firstWhere((l) => l?.userId == m.userId, orElse: () => null);
      if (loc == null) continue;
      if (_isRecentlyActive(_parseTimestamp(loc.timestamp))) live += 1;
    }
    return live;
  }

  DateTime? _parseTimestamp(String? ts) {
    if (ts == null) return null;
    try {
      return DateTime.parse(ts).toLocal();
    } catch (_) {
      return null;
    }
  }

  String? _endsInLabel() {
    final ts = widget.room.expirationTimestamp;
    if (ts == 0) return null;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remaining = ts - now;
    if (remaining <= 0) return 'expired';
    final hours = remaining ~/ 3600;
    final minutes = (remaining % 3600) ~/ 60;
    if (hours > 0 && minutes > 0) return 'ends in ${hours}h ${minutes}m';
    if (hours > 0) return 'ends in ${hours}h';
    return 'ends in ${minutes}m';
  }

  String? _endsAtClock() {
    final ts = widget.room.expirationTimestamp;
    if (ts == 0) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final hour = at.hour;
    final minute = at.minute;
    final isPm = hour >= 12;
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final mm = minute.toString().padLeft(2, '0');
    final clock = '$h12:$mm ${isPm ? 'PM' : 'AM'}';

    // Anything later than tomorrow is hard to interpret as a bare clock
    // time — prefix it with the weekday (or the date if it's > 6 days
    // out) so the user knows we mean Monday, not "today at 8:58 PM".
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(at.year, at.month, at.day);
    final daysUntil = endDay.difference(today).inDays;
    if (daysUntil <= 0) return clock;
    if (daysUntil == 1) return 'tomorrow, $clock';
    if (daysUntil < 7) return '${_weekday(at.weekday)}, $clock';
    return '${at.month}/${at.day}, $clock';
  }

  String _weekday(int weekday) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[(weekday - 1) % 7];
  }

  // ── builders ───────────────────────────────────────────────────────

  Widget _buildHeader(int liveCount) {
    final endsIn = _endsInLabel();
    final memberCount = _filteredMembers.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.02,
                    color: context.gridColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showGroupDetailsMenu,
                  borderRadius: BorderRadius.circular(GridTokens.rMd),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.gridColors.surface2,
                      borderRadius: BorderRadius.circular(GridTokens.rMd),
                      border: Border.all(color: context.gridColors.hairline),
                    ),
                    child: Icon(
                      Icons.more_horiz,
                      color: context.gridColors.text2,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MonoSummary(
            liveCount: liveCount,
            memberCount: memberCount,
            endsIn: endsIn,
          ),
        ],
      ),
    );
  }

  Widget? _buildAutoStopCard() {
    final endsAt = _endsAtClock();
    if (endsAt == null) return null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: context.gridColors.amberSoft,
          borderRadius: BorderRadius.circular(GridTokens.rMd),
          border: Border.all(color: context.gridColors.amber.withOpacity(0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.gridColors.amber.withOpacity(0.18),
                borderRadius: BorderRadius.circular(GridTokens.rSm),
              ),
              child: Icon(
                Icons.history,
                color: context.gridColors.amber,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Auto-stops at $endsAt',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.01,
                      color: context.gridColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sharing pauses automatically',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 12.5,
                      color: context.gridColors.text2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberRow(GridUser user, GroupsLoaded state,
      List<UserLocation> userLocations,
      {bool showDivider = false}) {
    final userLocation = userLocations
        .cast<UserLocation?>()
        .firstWhere((l) => l?.userId == user.userId, orElse: () => null);

    final memberStatus = state.getMemberStatus(user.userId);
    final lastUpdateAt =
        userLocation != null ? _parseTimestamp(userLocation.timestamp) : null;
    final timeAgoText = userLocation != null
        ? TimeAgoFormatter.format(userLocation.timestamp)
        : 'Offline';

    final currentHomeserver = widget.roomService.getMyHomeserver();
    final showFullMatrixId = isCustomHomeserver(currentHomeserver);

    final handle = showFullMatrixId
        ? user.userId
        : '@${user.userId.split(':')[0].replaceFirst('@', '')}';
    final name = user.displayName ?? localpart(user.userId);

    final isInvited = memberStatus == 'invite';
    // Dot is freshness-only; invited members get idle (the INVITED pill
    // carries the membership semantic).
    final avatarStatus =
        isInvited ? GridAvatarStatus.idle : statusFromLastUpdate(lastUpdateAt);

    String? statusLabel;
    GridStatusKind? statusKind;
    if (isInvited) {
      statusKind = GridStatusKind.paused;
      statusLabel = 'INVITED';
    }

    return GridContactRow(
      name: name,
      handle: handle,
      userId: user.userId,
      placeLine: _placeLine(timeAgoText, isInvited),
      timeText: isInvited ? null : timeAgoText,
      distanceText: null,
      statusKind: statusKind,
      statusLabel: statusLabel,
      avatarStatus: avatarStatus,
      showDivider: showDivider,
      onTap: isInvited
          ? null
          : () => _openMemberSheet(user, timeAgoText, lastUpdateAt),
    );
  }

  String? _placeLine(String timeAgoText, bool isInvited) {
    if (isInvited) return 'Invite pending';
    if (timeAgoText == 'Offline') return "Hasn't shared yet";
    return 'Sharing location';
  }

  bool _isRecentlyActive(DateTime? lastUpdateAt) =>
      statusFromLastUpdate(lastUpdateAt) == GridAvatarStatus.live;

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [context.gridColors.mintFaint, context.gridColors.surface],
          ),
          borderRadius: BorderRadius.circular(GridTokens.rLg),
          border: Border.all(color: context.gridColors.mintSoft),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    context.gridColors.mint.withValues(alpha: 0.22),
                    context.gridColors.mint.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: context.gridColors.mintSoft),
              ),
              child: Icon(
                Icons.person_add_alt_1_rounded,
                size: 28,
                color: context.gridColors.mint,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Just you in here',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.015,
                color: context.gridColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add people so you can see each other on the map.',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                color: context.gridColors.text2,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            GridButton(
              label: 'Add a member',
              icon: Icons.person_add_outlined,
              height: 46,
              onPressed: _showAddGroupMemberModal,
            ),
          ],
        ),
      ),
    );
  }

  /// Trailing group-actions block: primary "Add a member" + danger ghost
  /// "Leave group". The Add button is suppressed when the empty state
  /// is showing, since that state already surfaces an Add CTA.
  Widget _buildGroupActions() {
    final showAdd = _filteredMembers.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showAdd) ...[
            GridButton(
              label: 'Add a member',
              icon: Icons.person_add_outlined,
              onPressed: _showAddGroupMemberModal,
            ),
            const SizedBox(height: 8),
          ],
          Opacity(
            opacity: _isLeaving ? 0.5 : 1,
            child: GridButton(
              label: _isLeaving ? 'Leaving…' : 'Leave group',
              icon: Icons.exit_to_app_outlined,
              style: GridButtonStyle.danger,
              onPressed: _isLeaving ? null : _showLeaveConfirmationDialog,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userLocations =
        Provider.of<UserLocationProvider>(context).getAllUserLocations();

    return BlocBuilder<GroupsBloc, GroupsState>(
      buildWhen: (previous, current) {
        if (previous is GroupsLoaded && current is GroupsLoaded) {
          return previous.selectedRoomId != current.selectedRoomId ||
              previous.selectedRoomMembers != current.selectedRoomMembers ||
              previous.membershipStatuses != current.membershipStatuses;
        }
        return true;
      },
      builder: (context, state) {
        if (state is! GroupsLoaded) {
          return Column(
            children: [
              CustomSearchBar(
                controller: _searchController,
                hintText: 'Search Members',
              ),
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: context.gridColors.mint,
                  ),
                ),
              ),
            ],
          );
        }

        if (state.selectedRoomMembers != null && _currentUserId != null) {
          final searchText = _searchController.text.toLowerCase();
          _filteredMembers = state.selectedRoomMembers!
              .where((user) => user.userId != _currentUserId)
              .where((user) =>
                  (user.displayName?.toLowerCase().contains(searchText) ??
                      false) ||
                  user.userId.toLowerCase().contains(searchText))
              .toList();
        }

        final liveCount = _liveCount(state, userLocations);
        final autoStopCard = _buildAutoStopCard();

        return FadeTransition(
          opacity: _fadeAnimation,
          child: CustomScrollView(
            controller: widget.scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(liveCount),
                    if (autoStopCard != null) autoStopCard,
                    const SizedBox(height: 4),
                    const GridSectionHeader(text: 'MEMBERS'),
                    // Only show the search bar once the group has enough
                    // members for it to be useful — keeps the empty / small
                    // group state cleaner. (`6` is roughly the visible row
                    // budget in the sheet before scrolling.)
                    if ((state.selectedRoomMembers?.length ?? 0) > 6)
                      CustomSearchBar(
                        controller: _searchController,
                        hintText: 'Search members',
                      ),
                  ],
                ),
              ),
              if (_filteredMembers.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyState())
              else
                SliverList.builder(
                  itemCount: _filteredMembers.length,
                  itemBuilder: (context, index) {
                    final user = _filteredMembers[index];
                    final isLast = index == _filteredMembers.length - 1;
                    return _buildMemberRow(
                      user,
                      state,
                      userLocations,
                      showDivider: !isLast,
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Mono summary line under the group title:
/// `3 LIVE · 4 MEMBERS · ends in 3h 12m`.
class _MonoSummary extends StatelessWidget {
  const _MonoSummary({
    required this.liveCount,
    required this.memberCount,
    required this.endsIn,
  });

  final int liveCount;
  final int memberCount;
  final String? endsIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _LiveSegment(count: liveCount),
        _dot(context),
        GridMono(
          '$memberCount MEMBERS',
          color: context.gridColors.text2,
          size: 10.5,
          letterSpacing: 0.08,
        ),
        if (endsIn != null) ...[
          const Spacer(),
          Flexible(
            child: GridMono(
              endsIn!,
              color: context.gridColors.text3,
              size: 10.5,
              letterSpacing: 0.08,
              uppercase: false,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ],
    );
  }

  Widget _dot(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          '·',
          style: TextStyle(
            color: context.gridColors.text3,
            fontSize: 11,
            height: 1,
          ),
        ),
      );
}

class _LiveSegment extends StatelessWidget {
  const _LiveSegment({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: context.gridColors.mint,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        GridMono(
          '$count LIVE',
          color: context.gridColors.mint,
          size: 10.5,
          letterSpacing: 0.1,
        ),
      ],
    );
  }
}
