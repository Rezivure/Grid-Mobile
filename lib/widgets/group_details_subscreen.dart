import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

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
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/widgets/group_avatar_bloc.dart';
import 'package:grid_frontend/widgets/group_markers_modal.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_contact_row.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_segmented.dart';
import 'package:grid_frontend/widgets/grid/grid_status_pill.dart';

import 'user_avatar_bloc.dart';
import '../blocs/groups/groups_event.dart';
import '../blocs/groups/groups_state.dart';
import '../services/user_service.dart';
import '../utilities/time_ago_formatter.dart';
import 'add_group_member_modal.dart';
import 'location_history_modal.dart';

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

  Future<bool> _canCurrentUserKick() async {
    try {
      final room = widget.roomService.client.getRoomById(widget.room.roomId);
      return room?.canKick ?? false;
    } catch (e) {
      print('Error checking kick permissions: $e');
      return false;
    }
  }

  Future<bool> _isUserAContact(String userId) async {
    try {
      final directRoom =
          await widget.userRepository.getDirectRoomForContact(userId);
      return directRoom != null;
    } catch (e) {
      print('Error checking if user is contact: $e');
      return false;
    }
  }

  void _showExpandedAvatar(BuildContext context, String userId) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: Hero(
                tag: 'member_menu_avatar_$userId',
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  height: MediaQuery.of(context).size.width * 0.8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: GridTokens.surface,
                  ),
                  child: ClipOval(
                    child: UserAvatarBloc(
                      userId: userId,
                      size: MediaQuery.of(context).size.width * 0.8,
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

  Future<void> _kickMember(String userId) async {
    try {
      final success = await widget.roomService
          .kickMemberFromRoom(widget.room.roomId, userId);

      if (mounted) {
        if (success) {
          _showToast('User removed from group', danger: false);

          context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));

          await context
              .read<GroupsBloc>()
              .handleMemberKicked(widget.room.roomId, userId);

          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              context
                  .read<GroupsBloc>()
                  .add(LoadGroupMembers(widget.room.roomId));
            }
          });
        } else {
          _showToast(
              'Failed to remove user. You may not have permission.',
              danger: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showToast('Error removing user: $e', danger: true);
      }
    }
  }

  void _showToast(String text, {required bool danger}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor:
            danger ? GridTokens.danger : GridTokens.mint,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GridTokens.rMd),
        ),
      ),
    );
  }

  void _showMemberMenu(GridUser user, String? memberStatus) async {
    final canKick = await _canCurrentUserKick();

    final currentHomeserver = widget.roomService.getMyHomeserver();
    final showFullMatrixId = isCustomHomeserver(currentHomeserver);

    final isAlreadyContact = await _isUserAContact(user.userId);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: GridTokens.surface,
            borderRadius: BorderRadius.circular(GridTokens.rLg),
            border: Border.all(color: GridTokens.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Member info header
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: GridTokens.surface2,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(GridTokens.rLg),
                    topRight: Radius.circular(GridTokens.rLg),
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () =>
                          _showExpandedAvatar(context, user.userId),
                      child: Hero(
                        tag: 'member_menu_avatar_${user.userId}',
                        child: ClipOval(
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: UserAvatarBloc(
                              userId: user.userId,
                              size: 56,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayName ?? localpart(user.userId),
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.015,
                              color: GridTokens.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          GridMono(
                            showFullMatrixId
                                ? user.userId
                                : '@${user.userId.split(':')[0].replaceFirst('@', '')}',
                            color: GridTokens.text3,
                            size: 11,
                            uppercase: false,
                            letterSpacing: 0,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    _menuRow(
                      icon: Icons.person_add_outlined,
                      label: isAlreadyContact
                          ? 'Already in contacts'
                          : 'Send friend request',
                      tint: isAlreadyContact
                          ? GridTokens.text4
                          : GridTokens.mint,
                      bgTint: isAlreadyContact
                          ? GridTokens.surface3
                          : GridTokens.mintFaint,
                      onTap: isAlreadyContact
                          ? null
                          : () {
                              Navigator.pop(context);
                              _showFriendRequestConfirmation(
                                  user, showFullMatrixId);
                            },
                    ),
                    _menuRow(
                      icon: Icons.person_remove_outlined,
                      label: 'Remove from group',
                      tint: canKick
                          ? GridTokens.danger
                          : GridTokens.text4,
                      bgTint: canKick
                          ? GridTokens.dangerSoft
                          : GridTokens.surface3,
                      onTap: canKick
                          ? () {
                              Navigator.pop(context);
                              _showKickConfirmation(user);
                            }
                          : null,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _menuRow({
    required IconData icon,
    required String label,
    required Color tint,
    required Color bgTint,
    VoidCallback? onTap,
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
                        ? GridTokens.text4
                        : (tint == GridTokens.danger
                            ? GridTokens.danger
                            : GridTokens.text),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFriendRequestConfirmation(GridUser user, bool showFullMatrixId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            decoration: BoxDecoration(
              color: GridTokens.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: GridTokens.hairline),
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
                  decoration: const BoxDecoration(
                    color: GridTokens.mintFaint,
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
                          color: GridTokens.mintSoft,
                          borderRadius:
                              BorderRadius.circular(GridTokens.rMd),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.person_add,
                          color: GridTokens.mint,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Send friend request',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.015,
                                color: GridTokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "They'll need to accept the request.",
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: GridTokens.text2,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send a friend request to:',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: GridTokens.text2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: GridTokens.surface2,
                          borderRadius:
                              BorderRadius.circular(GridTokens.rMd),
                          border: Border.all(color: GridTokens.hairline),
                        ),
                        child: Row(
                          children: [
                            ClipOval(
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: UserAvatarBloc(
                                  userId: user.userId,
                                  size: 48,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.displayName ??
                                        localpart(user.userId),
                                    style: GoogleFonts.getFont(
                                      'Geist',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: GridTokens.text,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  GridMono(
                                    showFullMatrixId
                                        ? user.userId
                                        : '@${user.userId.split(':')[0].replaceFirst('@', '')}',
                                    color: GridTokens.text3,
                                    size: 11,
                                    uppercase: false,
                                    letterSpacing: 0,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GridButton(
                          label: 'Send',
                          style: GridButtonStyle.primary,
                          onPressed: () async {
                            Navigator.pop(context);
                            await _sendFriendRequest(user);
                          },
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
  }

  Future<void> _sendFriendRequest(GridUser user) async {
    try {
      final success =
          await widget.roomService.createRoomAndInviteContact(user.userId);

      if (!mounted) return;

      if (success) {
        _showToast(
          'Friend request sent to ${user.displayName ?? localpart(user.userId)}',
          danger: false,
        );
      } else {
        _showToast(
          'Failed to send friend request. User may not exist or is already a contact.',
          danger: true,
        );
      }
    } catch (e) {
      print('Error sending friend request: $e');
      if (mounted) {
        _showToast('Error sending friend request: ${e.toString()}',
            danger: true);
      }
    }
  }

  void _showKickConfirmation(GridUser user) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            decoration: BoxDecoration(
              color: GridTokens.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: GridTokens.hairline),
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
                  decoration: const BoxDecoration(
                    color: GridTokens.dangerSoft,
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
                          color: GridTokens.danger.withOpacity(0.18),
                          borderRadius:
                              BorderRadius.circular(GridTokens.rMd),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.person_remove_outlined,
                          color: GridTokens.danger,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Remove member',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.015,
                                color: GridTokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "They'll lose access to this group.",
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: GridTokens.text2,
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
                    'Are you sure you want to remove "${user.displayName ?? localpart(user.userId)}" from this group?',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: GridTokens.text2,
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
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GridButton(
                          label: 'Remove',
                          style: GridButtonStyle.danger,
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _kickMember(user.userId);
                          },
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
              color: GridTokens.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: GridTokens.hairline),
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
                  decoration: const BoxDecoration(
                    color: GridTokens.dangerSoft,
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
                          color: GridTokens.danger.withOpacity(0.18),
                          borderRadius:
                              BorderRadius.circular(GridTokens.rMd),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.exit_to_app,
                          color: GridTokens.danger,
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
                                color: GridTokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "This action cannot be undone.",
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: GridTokens.text2,
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
                      color: GridTokens.text2,
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
        _showToast('You have left the group', danger: false);
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
        decoration: const BoxDecoration(
          color: GridTokens.surface,
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

  void _showGroupMarkersModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GroupMarkersModal(
        roomId: widget.room.roomId,
        roomName: _groupName,
        mapIconRepository: MapIconRepository(DatabaseService()),
      ),
    );
  }

  void _showGroupDetailsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: GridTokens.surface,
            borderRadius: BorderRadius.circular(GridTokens.rLg),
            border: Border.all(color: GridTokens.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Group info header
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: GridTokens.surface2,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(GridTokens.rLg),
                    topRight: Radius.circular(GridTokens.rLg),
                  ),
                ),
                child: Row(
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: GroupAvatarBloc(
                          roomId: widget.room.roomId,
                          memberIds: widget.room.members,
                          size: 56,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _groupName,
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.015,
                              color: GridTokens.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          GridMono(
                            '${_filteredMembers.length} MEMBERS',
                            color: GridTokens.text3,
                            size: 10.5,
                            letterSpacing: 0.08,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              _menuRow(
                icon: Icons.person_add_outlined,
                label: 'Add member',
                tint: GridTokens.mint,
                bgTint: GridTokens.mintFaint,
                onTap: () {
                  Navigator.pop(context);
                  _showAddGroupMemberModal();
                },
              ),
              _menuRow(
                icon: Icons.history,
                label: 'View history',
                tint: GridTokens.mint,
                bgTint: GridTokens.mintFaint,
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (BuildContext context) {
                      return LocationHistoryModal(
                        userId: widget.room.roomId,
                        userName: _groupName,
                        memberIds:
                            _filteredMembers.map((m) => m.userId).toList(),
                      );
                    },
                  );
                },
              ),
              _menuRow(
                icon: Icons.location_on,
                label: 'View markers',
                tint: GridTokens.mint,
                bgTint: GridTokens.mintFaint,
                onTap: () {
                  Navigator.pop(context);
                  _showGroupMarkersModal();
                },
              ),
              _menuRow(
                icon: Icons.exit_to_app_outlined,
                label: 'Leave group',
                tint: GridTokens.danger,
                bgTint: GridTokens.dangerSoft,
                onTap: _isLeaving
                    ? null
                    : () {
                        Navigator.pop(context);
                        _showLeaveConfirmationDialog();
                      },
              ),
              const SizedBox(height: 12),
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
      final ago = TimeAgoFormatter.format(loc.timestamp);
      if (_isRecentlyActive(ago)) live += 1;
    }
    return live;
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
                    color: GridTokens.text,
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
                      color: GridTokens.surface2,
                      borderRadius: BorderRadius.circular(GridTokens.rMd),
                      border: Border.all(color: GridTokens.hairline),
                    ),
                    child: const Icon(
                      Icons.more_horiz,
                      color: GridTokens.text2,
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
          color: GridTokens.amberSoft,
          borderRadius: BorderRadius.circular(GridTokens.rMd),
          border: Border.all(color: GridTokens.amber.withOpacity(0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: GridTokens.amber.withOpacity(0.18),
                borderRadius: BorderRadius.circular(GridTokens.rSm),
              ),
              child: const Icon(
                Icons.history,
                color: GridTokens.amber,
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
                      color: GridTokens.text,
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
                      color: GridTokens.text2,
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
    final timeAgoText = userLocation != null
        ? TimeAgoFormatter.format(userLocation.timestamp)
        : 'Offline';

    final currentHomeserver = widget.roomService.getMyHomeserver();
    final showFullMatrixId = isCustomHomeserver(currentHomeserver);

    final handle = showFullMatrixId
        ? user.userId
        : '@${user.userId.split(':')[0].replaceFirst('@', '')}';
    final name = user.displayName ?? localpart(user.userId);

    // Map status into avatar dot tokens.
    final isInvited = memberStatus == 'invite';
    final isLive = !isInvited && _isRecentlyActive(timeAgoText);
    final isPaused = !isInvited &&
        !isLive &&
        (timeAgoText.contains('m ago') ||
            timeAgoText.contains('h ago'));

    final avatarStatus = isInvited
        ? GridAvatarStatus.paused
        : isLive
            ? GridAvatarStatus.live
            : isPaused
                ? GridAvatarStatus.paused
                : GridAvatarStatus.offline;

    String? statusLabel;
    GridStatusKind? statusKind;
    if (isInvited) {
      statusKind = GridStatusKind.paused;
      statusLabel = 'INVITED';
    } else if (timeAgoText == 'Offline') {
      // no pill — offline avatar dot conveys it
    } else if (isLive) {
      // live badge is already shown next to the name
    } else if (isPaused) {
      statusKind = GridStatusKind.paused;
      statusLabel = 'PAUSED';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Provider.of<SelectedUserProvider>(context, listen: false)
              .setSelectedUserId(user.userId, context);
        },
        onLongPress: () => _showMemberMenu(user, memberStatus),
        child: IgnorePointer(
          // Tapping passes through to the InkWell above; ContactRow shouldn't
          // own its own tap because we need long-press for the action menu.
          child: GridContactRow(
            name: name,
            handle: handle,
            placeLine: _placeLine(timeAgoText, isInvited),
            timeText: isInvited
                ? null
                : (timeAgoText == 'Offline' ? null : timeAgoText),
            distanceText: null,
            statusKind: statusKind,
            statusLabel: statusLabel,
            live: isLive,
            avatarStatus: avatarStatus,
            showDivider: showDivider,
          ),
        ),
      ),
    );
  }

  String? _placeLine(String timeAgoText, bool isInvited) {
    if (isInvited) return 'pending invite';
    if (timeAgoText == 'Offline') return 'offline';
    return null;
  }

  bool _isRecentlyActive(String timeAgo) {
    if (timeAgo == 'Just now' || timeAgo.contains('s ago')) {
      return true;
    }
    if (timeAgo.contains('m ago') && !timeAgo.contains('h')) {
      final minutesMatch = RegExp(r'(\d+)m ago').firstMatch(timeAgo);
      if (minutesMatch != null) {
        final minutes = int.parse(minutesMatch.group(1)!);
        return minutes <= 10;
      }
    }
    return false;
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [GridTokens.mintFaint, GridTokens.surface],
          ),
          borderRadius: BorderRadius.circular(GridTokens.rLg),
          border: Border.all(color: GridTokens.mintSoft),
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
                    GridTokens.mint.withValues(alpha: 0.22),
                    GridTokens.mint.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: GridTokens.mintSoft),
              ),
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                size: 28,
                color: GridTokens.mint,
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
                color: GridTokens.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add people so you can see each other on the map.',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                color: GridTokens.text2,
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
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: GridTokens.mint,
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
        _dot(),
        GridMono(
          '$memberCount MEMBERS',
          color: GridTokens.text2,
          size: 10.5,
          letterSpacing: 0.08,
        ),
        if (endsIn != null) ...[
          const Spacer(),
          Flexible(
            child: GridMono(
              endsIn!,
              color: GridTokens.text3,
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

  Widget _dot() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          '·',
          style: TextStyle(
            color: GridTokens.text3,
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
          decoration: const BoxDecoration(
            color: GridTokens.mint,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        GridMono(
          '$count LIVE',
          color: GridTokens.mint,
          size: 10.5,
          letterSpacing: 0.1,
        ),
      ],
    );
  }
}
