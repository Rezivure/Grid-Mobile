import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_segmented.dart';
import 'package:grid_frontend/blocs/invitations/invitations_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_state.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_state.dart';
import 'package:grid_frontend/models/room.dart' as GridRoom;
import 'package:grid_frontend/widgets/profile_modal.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';
import 'package:grid_frontend/blocs/groups/groups_state.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:grid_frontend/blocs/invitations/invitations_event.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'contacts_subscreen.dart';
import 'groups_subscreen.dart';
import 'invites_modal.dart';
import 'group_details_subscreen.dart';
import 'triangle_avatars.dart';
import 'add_friend_modal.dart';
import '../providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'group_avatar.dart';
import 'group_avatar_bloc.dart';
import 'user_avatar_bloc.dart';
import 'location_history_modal.dart';
import 'add_group_member_modal.dart';
import 'group_markers_modal.dart';
import '../repositories/map_icon_repository.dart';
import '../services/database_service.dart';
import 'package:grid_frontend/screens/settings/settings_page.dart';

class MapScrollWindow extends StatefulWidget {
  final bool isEditingMapIcon;

  const MapScrollWindow({
    Key? key,
    this.isEditingMapIcon = false,
  }) : super(key: key);

  @override
  _MapScrollWindowState createState() => _MapScrollWindowState();
}

enum SubscreenOption { contacts, groups, invites, groupDetails }

class _MapScrollWindowState extends State<MapScrollWindow> 
    with TickerProviderStateMixin {
  late final RoomService _roomService;
  late final UserService _userService;
  late final LocationRepository _locationRepository;
  late final UserRepository _userRepository;
  late final RoomRepository _roomRepository;
  late final GroupsBloc _groupsBloc;
  late final SharingPreferencesRepository sharingPreferencesRepository;

  SubscreenOption _selectedOption = SubscreenOption.contacts;
  bool _isDropdownExpanded = false;
  String _selectedLabel = 'My Contacts';
  GridRoom.Room? _selectedRoom;
  bool _isScrollingContent = false;
  String? _cachedUserId; // Cache user ID to avoid repeated fetches

  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final DraggableScrollableController _scrollableController =
      DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _roomService = context.read<RoomService>();
    _userService = context.read<UserService>();
    _locationRepository = context.read<LocationRepository>();
    _userRepository = context.read<UserRepository>();
    _roomRepository = context.read<RoomRepository>();
    _groupsBloc = context.read<GroupsBloc>();
    sharingPreferencesRepository = context.read<SharingPreferencesRepository>();

    // Initialize animations
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _groupsBloc.add(LoadGroups());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SelectedSubscreenProvider>(context, listen: false)
          .setSelectedSubscreen('contacts');

      // Preload group avatars after frame is built
      _preloadGroupAvatars();
    });

    // Load and cache user ID once
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final userId = await _userService.getMyUserId();
    if (mounted) {
      setState(() {
        _cachedUserId = userId;
      });
    }
  }

  // Preload all group avatars to avoid flicker
  Future<void> _preloadGroupAvatars() async {
    // No need for implementation here anymore - we'll use Offstage widgets
  }

  @override
  void dispose() {
    _expandController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<List<GridRoom.Room>> _fetchGroupRooms() async {
    return await _roomRepository.getNonExpiredRooms();
  }

  void _showInvitesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => BlocProvider.value(
        value: context.read<InvitationsBloc>(),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(modalContext).size.height * 0.95,
          ),
          decoration: BoxDecoration(
            color: Theme.of(modalContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(modalContext).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: InvitesModal(
              roomService: _roomService,
              onInviteHandled: _navigateToContacts,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    return Stack(
      children: [
        // Preload group avatars offstage to prevent flicker
        BlocBuilder<GroupsBloc, GroupsState>(
          builder: (context, state) {
            if (state is GroupsLoaded) {
              return Offstage(
                offstage: true,
                child: Row(
                  children: state.groups.map((group) {
                    return GroupAvatarBloc(
                      key: ValueKey('preload_${group.roomId}'),
                      roomId: group.roomId,
                      memberIds: group.members,
                      size: 36,
                    );
                  }).toList(),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        // Main draggable sheet with FAB
        Stack(
          children: [
            DraggableScrollableSheet(
              controller: _scrollableController,
              initialChildSize: 0.45,
              minChildSize: 0.3,
              maxChildSize: 0.7,
              builder: (BuildContext context, ScrollController scrollController) {
                return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              _isScrollingContent = true;
            } else if (notification is ScrollEndNotification) {
              _isScrollingContent = false;
            }
            return true;
          },
          child: AnimatedOpacity(
            opacity: widget.isEditingMapIcon ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: BoxDecoration(
                // One uniform surface for the entire sheet body (handle,
                // segmented header, subscreen). context.gridColors.surface == #15181B
                // — matches what the segmented pill renders against so the
                // top of the sheet doesn't look gray-on-near-black.
                color: context.gridColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.15),
                  blurRadius: 20.0,
                  spreadRadius: 0,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                // Drag Handle Area - Make this draggable
                GestureDetector(
                  onVerticalDragUpdate: (details) {
                    final delta = details.delta.dy / MediaQuery.of(context).size.height;
                    final newSize = (_scrollableController.size - delta)
                        .clamp(0.3, 0.7);
                    _scrollableController.jumpTo(newSize);
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Header Section — new segmented tabs.
                _buildSegmentedHeader(colorScheme),
                
                // Content — paint the same surface underneath the subscreen
                // so the area between the segmented header and the subscreen
                // body never reveals the underlying scaffold.
                Expanded(
                  child: ColoredBox(
                    color: context.gridColors.surface,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.pixels <= 0 &&
                            notification is ScrollUpdateNotification &&
                            notification.dragDetails != null &&
                            !_isScrollingContent) {
                          final delta = notification.dragDetails!.delta.dy /
                              MediaQuery.of(context).size.height;
                          final newSize = (_scrollableController.size - delta)
                              .clamp(0.3, 0.7);
                          _scrollableController.jumpTo(newSize);
                          return true;
                        }
                        return false;
                      },
                      child: _buildSubscreen(scrollController),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),  // End of AnimatedOpacity
        );  // End of NotificationListener
      },
    ),  // End of DraggableScrollableSheet
    ],  // End of Stack children
    ),  // End of Stack
    ],
  );
  }

  /// New segmented tabs header: People · Groups · Invites + search field.
  /// Replaces the old dropdown header. Invites segment opens the existing
  /// invites modal (preserves current routing behavior).
  Widget _buildSegmentedHeader(ColorScheme colorScheme) {
    final int contactCount = _contactsLiveCount();
    final int groupCount = _groupsCount();
    final int inviteCount = _invitesCount();

    // groupDetails is a child view of Groups — keep the Groups pill lit when
    // a specific group is selected so the segmented control doesn't snap
    // back to People on group-tap.
    final bool isGroupsView = _selectedOption == SubscreenOption.groups ||
        _selectedOption == SubscreenOption.groupDetails;
    final bool isInvitesView = _selectedOption == SubscreenOption.invites;
    final int selected =
        isInvitesView ? 2 : (isGroupsView ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: GridSegmented(
                  selected: selected,
                  tabs: [
                    GridSegmentedTab(label: 'People', badgeCount: contactCount),
                    GridSegmentedTab(label: 'Groups', badgeCount: groupCount),
                    GridSegmentedTab(
                      label: 'Invites',
                      badgeCount: inviteCount,
                      badgeColor: context.gridColors.amber,
                    ),
                  ],
                  onChanged: (i) {
                    setState(() {
                      _selectedOption = switch (i) {
                        2 => SubscreenOption.invites,
                        1 => SubscreenOption.groups,
                        _ => SubscreenOption.contacts,
                      };
                    });
                    Provider.of<SelectedSubscreenProvider>(context,
                            listen: false)
                        .setSelectedSubscreen(switch (i) {
                      2 => 'invites',
                      1 => 'groups',
                      _ => 'contacts',
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Swap based on the active pill — Add Friend on
                  // People, Create Group on Groups. Defaults to Add
                  // Friend on Invites (since Invites is read-only).
                  GridNavIconButton(
                    icon: isGroupsView
                        ? Icons.group_add_outlined
                        : Icons.person_add_outlined,
                    size: 40,
                    onPressed: () => isGroupsView
                        ? _showCreateGroupModal(context)
                        : _showAddFriendModal(context),
                  ),
                  const SizedBox(width: 8),
                  GridNavIconButton(
                    icon: Icons.settings_outlined,
                    size: 40,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SettingsPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Search field lives inside each subscreen — don't render here.
        ],
      ),
    );
  }

  int _contactsLiveCount() {
    try {
      final s = context.read<ContactsBloc>().state;
      if (s is ContactsLoaded) {
        return s.contacts.length;
      }
    } catch (_) {}
    return 0;
  }

  int _groupsCount() {
    try {
      final s = context.read<GroupsBloc>().state;
      if (s is GroupsLoaded) return s.groups.length;
    } catch (_) {}
    return 0;
  }

  int _invitesCount() {
    try {
      final s = context.read<InvitationsBloc>().state;
      if (s is InvitationsLoaded) return s.invitations.length;
    } catch (_) {}
    return 0;
  }

  Widget _buildModernHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title Section with Dropdown
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isDropdownExpanded = !_isDropdownExpanded;
                  if (_isDropdownExpanded) {
                    _expandController.forward();
                    _fadeController.forward();
                    // Don't refresh groups every time dropdown opens
                    // _groupsBloc.add(RefreshGroups());
                  } else {
                    _expandController.reverse();
                    _fadeController.reverse();
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Text(
                        _selectedLabel,
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _isDropdownExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: colorScheme.onSurface.withOpacity(0.7),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Action Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show group icon when viewing a group, otherwise show add contact
              _selectedOption == SubscreenOption.groupDetails && _selectedRoom != null
                ? _buildGroupActionButton(
                    icon: Icons.group_outlined,
                    onPressed: () => _showGroupDetailsMenu(context),
                    colorScheme: colorScheme,
                    tooltip: 'Group Settings',
                  )
                : _buildActionButton(
                    icon: Icons.person_add_outlined,
                    onPressed: () => _showAddFriendModal(context),
                    colorScheme: colorScheme,
                    tooltip: 'Add Contact',
                  ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.qr_code_scanner_outlined,
                onPressed: () => _showProfileModal(context),
                colorScheme: colorScheme,
                tooltip: 'My QR Code',
              ),
              const SizedBox(width: 8),
              _buildNotificationButton(colorScheme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required ColorScheme colorScheme,
    String? tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: colorScheme.onSurface,
          size: 20,
        ),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildGroupActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required ColorScheme colorScheme,
    String? tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: colorScheme.primary,
          size: 20,
        ),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildNotificationButton(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Stack(
        children: [
          IconButton(
            icon: Icon(
              Icons.notifications_outlined,
              color: colorScheme.onSurface,
              size: 20,
            ),
            onPressed: () => _showInvitesModal(context),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: BlocBuilder<InvitationsBloc, InvitationsState>(
              builder: (context, state) {
                int inviteCount = 0;
                if (state is InvitationsLoaded) {
                  inviteCount = state.totalInvites;
                }
                
                if (inviteCount > 0) {
                  return Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$inviteCount',
                      style: TextStyle(
                        color: colorScheme.onError,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHorizontalScroller(ColorScheme colorScheme) {
    // Use cached user ID to avoid rebuilds
    if (_cachedUserId == null) {
      return Container(
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Center(
          child: CircularProgressIndicator(
            color: colorScheme.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }
    
    return BlocBuilder<GroupsBloc, GroupsState>(
      builder: (context, groupsState) {
        // Get and sort groups alphabetically by name
        final groups = (groupsState is GroupsLoaded)
            ? List<GridRoom.Room>.from(groupsState.groups)
            : <GridRoom.Room>[];
        
        // Sort groups alphabetically by their display name
        groups.sort((a, b) {
          final aName = a.name.split(':').length >= 5 ? a.name.split(':')[3] : a.name;
          final bName = b.name.split(':').length >= 5 ? b.name.split(':')[3] : b.name;
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        });

        final totalItems = groups.length + 1 + (groupsState is GroupsLoading ? 1 : 0);

        return SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
            itemCount: totalItems,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _buildModernContactOption(colorScheme, _cachedUserId!),
                );
              }
                  
                  final groupIndex = index - 1;
                  if (groupIndex < groups.length) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildModernGroupOption(colorScheme, groups[groupIndex]),
                    );
                  }
                  
                  // Loading indicator
                  if (groupsState is GroupsLoading) {
                    return Container(
                      width: 70,
                      alignment: Alignment.center,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    );
                  }
                  
                return const SizedBox.shrink();
              },
            ),
          );
        },
      );
    }

  Widget _buildModernContactOption(ColorScheme colorScheme, String userId) {
    final isSelected = _selectedLabel == 'My Contacts';

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedOption = SubscreenOption.contacts;
          _selectedLabel = 'My Contacts';
          _isDropdownExpanded = false;
          _expandController.reverse();
          _fadeController.reverse();
          Provider.of<SelectedSubscreenProvider>(context, listen: false)
              .setSelectedSubscreen('contacts');
        });
      },
      child: Container(
        width: 80,
        height: 100,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withOpacity(0.3)
                : colorScheme.outline.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: colorScheme.primary.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: UserAvatarBloc(
                userId: userId,
                size: 48,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 68, // Increased width to fit "Contacts" text
              child: Text(
                'Contacts',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.0,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernGroupOption(ColorScheme colorScheme, GridRoom.Room room) {
    final parts = room.name.split(':');
    if (parts.length >= 5) {
      final groupName = parts[3];
      final remainingTimeStr = room.expirationTimestamp == 0
          ? '∞'
          : _formatDuration(Duration(
              seconds: room.expirationTimestamp -
                  DateTime.now().millisecondsSinceEpoch ~/ 1000));

      final isSelected = _selectedLabel == groupName;

      return GestureDetector(
        onTap: () {
          setState(() {
            _selectedOption = SubscreenOption.groupDetails;
            _selectedLabel = groupName;
            _selectedRoom = room;
            _isDropdownExpanded = false;
            _expandController.reverse();
            _fadeController.reverse();
            Provider.of<SelectedSubscreenProvider>(context, listen: false)
                .setSelectedSubscreen('group:${room.roomId}');
          });
        },
        child: Container(
          width: 80,
          height: 100,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected 
                ? colorScheme.primaryContainer 
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected 
                  ? colorScheme.primary.withOpacity(0.3)
                  : colorScheme.outline.withOpacity(0.1),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: GroupAvatarBloc(
                      roomId: room.roomId,
                      memberIds: room.members,
                      size: 48,
                    ),
                  ),
                  if (room.expirationTimestamp > 0)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          remainingTimeStr,
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 68, // Increased width to match contacts
                child: Text(
                  groupName,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.0,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSubscreen(ScrollController scrollController) {
    switch (_selectedOption) {
      case SubscreenOption.groups:
        return GroupsSubscreen(
          scrollController: scrollController,
          onGroupSelected: (room) {
            setState(() {
              _selectedRoom = room;
              _selectedOption = SubscreenOption.groupDetails;
              _selectedLabel = room.name.split(':').length > 3
                  ? room.name.split(':')[3]
                  : room.name;
            });
            Provider.of<SelectedSubscreenProvider>(context, listen: false)
                .setSelectedSubscreen('group:${room.roomId}');
          },
        );
      case SubscreenOption.groupDetails:
        if (_selectedRoom != null) {
          return GroupDetailsSubscreen(
            roomService: _roomService,
            userService: _userService,
            userRepository: _userRepository,
            sharingPreferencesRepository: sharingPreferencesRepository,
            scrollController: scrollController,
            room: _selectedRoom!,
            onGroupLeft: _navigateToContacts,
          );
        }
        return Center(
          child: Text(
            'No group selected',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        );
      case SubscreenOption.invites:
        return InvitesSubscreen(
          scrollController: scrollController,
          roomService: _roomService,
          onInviteHandled: () async {
            try {
              context.read<InvitationsBloc>().add(LoadInvitations());
            } catch (_) {}
          },
        );
      case SubscreenOption.contacts:
      default:
        return ContactsSubscreen(
          roomService: _roomService,
          userRepository: _userRepository,
          sharingPreferencesRepository: sharingPreferencesRepository,
          scrollController: scrollController,
        );
    }
  }

  Future<void> _navigateToContacts() async {
    setState(() {
      _selectedOption = SubscreenOption.contacts;
      _selectedLabel = 'My Contacts';
      _isDropdownExpanded = false;
      _expandController.reverse();
      _fadeController.reverse();
      Provider.of<SelectedSubscreenProvider>(context, listen: false)
          .setSelectedSubscreen('contacts');
    });
  }

  void _showExpandedGroupAvatar(BuildContext context, GridRoom.Room room) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(20),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: Hero(
                  tag: 'group_drawer_avatar_${room.roomId}',
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.width * 0.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    child: ClipOval(
                      child: GroupAvatarBloc(
                        roomId: room.roomId,
                        memberIds: room.members,
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

  /// Opens the Add Friend modal pre-routed to the group-create flow.
  /// Used by the drawer header's contextual icon when the Groups pill
  /// is selected — `startInGroupCreate: true` skips the hub entirely.
  void _showCreateGroupModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.95,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: AddFriendModal(
          roomService: _roomService,
          userService: _userService,
          groupsBloc: _groupsBloc,
          startInGroupCreate: true,
          onGroupCreated: () {
            _groupsBloc.add(RefreshGroups());
          },
        ),
      ),
    );
  }

  void _showAddFriendModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.95,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: AddFriendModal(
              roomService: _roomService,
              userService: _userService,
              groupsBloc: _groupsBloc,
              onGroupCreated: () {
            // Force refresh right away
            _groupsBloc.add(RefreshGroups());

            // Force dropdown to open to show new group
            setState(() {
              _isDropdownExpanded = true;
              _expandController.forward();
              _fadeController.forward();
            });

            // Add a delayed refresh for sync completion
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                _groupsBloc.add(RefreshGroups());
                _groupsBloc.add(LoadGroups());
              }
            });
          },
        ),
      ),
    );
  }

  void _showProfileModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.95,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: ProfileModal(
            userService: _userService,
          ),
        ),
      ),
    );
  }


  void _showGroupDetailsMenu(BuildContext context, [GridRoom.Room? roomOverride]) {
    final room = roomOverride ?? _selectedRoom;
    if (room == null) return;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get current members from the groups bloc
    final groupsState = context.read<GroupsBloc>().state;
    final filteredMembers = groupsState is GroupsLoaded && groupsState.selectedRoomMembers != null
        ? groupsState.selectedRoomMembers!.where((user) =>
            user.userId != _cachedUserId).toList()
        : [];

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
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Group info header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        _showExpandedGroupAvatar(context, room);
                      },
                      child: Hero(
                        tag: 'group_drawer_avatar_${room.roomId}',
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: colorScheme.primary.withOpacity(0.1),
                          child: GroupAvatarBloc(
                            roomId: room.roomId,
                            memberIds: room.members,
                            size: 40,
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
                            room.name.split(':').length >= 5
                                ? room.name.split(':')[3]
                                : room.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            '${filteredMembers.length} members',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Add Member
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.person_add_outlined,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Add Member',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.95,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: AddGroupMemberModal(
                        roomId: room.roomId,
                        groupName: room.name.split(':').length >= 5
                            ? room.name.split(':')[3]
                            : room.name,
                        roomService: _roomService,
                        userService: _userService,
                        userRepository: _userRepository,
                        onInviteSent: null,
                      ),
                    ),
                  );
                },
              ),

              // View History
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.history,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  'View History',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (BuildContext context) {
                      return Container(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.95,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: LocationHistoryModal(
                          userId: room.roomId,
                          userName: room.name.split(':').length >= 5
                              ? room.name.split(':')[3]
                              : room.name,
                          memberIds: filteredMembers.map((m) => m.userId as String).toList(),
                        ),
                      );
                    },
                  );
                },
              ),

              // View Markers
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  'View Markers',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.95,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: GroupMarkersModal(
                        roomId: room.roomId,
                        roomName: room.name.split(':').length >= 5
                            ? room.name.split(':')[3]
                            : room.name,
                        mapIconRepository: MapIconRepository(DatabaseService()),
                      ),
                    ),
                  );
                },
              ),

              // Leave Group
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.exit_to_app_outlined,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Leave Group',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  // Show leave confirmation
                  final groupName = room.name.split(':').length >= 5
                      ? room.name.split(':')[3]
                      : room.name;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) {
                      return Dialog(
                        backgroundColor: Colors.transparent,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.9,
                          ),
                          decoration: BoxDecoration(
                            color: context.gridColors.surface,
                            borderRadius:
                                BorderRadius.circular(GridTokens.rXl),
                            border:
                                Border.all(color: context.gridColors.hairline),
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
                                    topLeft:
                                        Radius.circular(GridTokens.rXl),
                                    topRight:
                                        Radius.circular(GridTokens.rXl),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: context.gridColors.danger
                                            .withOpacity(0.18),
                                        borderRadius:
                                            BorderRadius.circular(
                                                GridTokens.rMd),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                padding: const EdgeInsets.fromLTRB(
                                    20, 18, 20, 0),
                                child: Text(
                                  'Are you sure you want to leave "$groupName"?',
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
                                padding: const EdgeInsets.fromLTRB(
                                    20, 18, 20, 20),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GridButton(
                                        label: 'Cancel',
                                        style: GridButtonStyle.secondary,
                                        onPressed: () => Navigator.of(
                                                context)
                                            .pop(false),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: GridButton(
                                        label: 'Leave',
                                        style: GridButtonStyle.danger,
                                        onPressed: () => Navigator.of(
                                                context)
                                            .pop(true),
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

                  if (confirmed == true) {
                    try {
                      await _roomService.leaveRoom(room.roomId);
                      _navigateToContacts();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Left group successfully')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error leaving group: $e')),
                        );
                      }
                    }
                  }
                },
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else if (duration.inSeconds >= 0) {
      return '${duration.inSeconds}s';
    } else {
      return '';
    }
  }
}