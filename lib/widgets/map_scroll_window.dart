import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/models/room.dart' as GridRoom;
import 'package:grid_frontend/widgets/profile_modal.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';


import '../blocs/groups/groups_state.dart';
import '../services/sync_manager.dart';
import '../utilities/utils.dart';
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

class MapScrollWindow extends StatefulWidget {
  const MapScrollWindow({Key? key}) : super(key: key);

  @override
  _MapScrollWindowState createState() => _MapScrollWindowState();
}

enum SubscreenOption { contacts, groups, invites, groupDetails }

class _MapScrollWindowState extends State<MapScrollWindow> {
  late final RoomService _roomService;
  late final UserService _userService;
  late final LocationRepository _locationRepository;
  late final UserRepository _userRepository;
  late final RoomRepository _roomRepository;
  late final GroupsBloc _groupsBloc;

  SubscreenOption _selectedOption = SubscreenOption.contacts;
  bool _isDropdownExpanded = false;
  String _selectedLabel = 'My Contacts';
  GridRoom.Room? _selectedRoom;


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

    _groupsBloc.add(LoadGroups());


    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SelectedSubscreenProvider>(context, listen: false)
          .setSelectedSubscreen('contacts');
    });
  }

  Future<List<GridRoom.Room>> _fetchGroupRooms() async {
    return await _roomRepository.getNonExpiredRooms();
  }

  void _showInvitesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: InvitesModal(
          roomService: _roomService,
          onInviteHandled: _navigateToContacts,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      controller: _scrollableController,
      initialChildSize: 0.3,
      minChildSize: 0.3,
      maxChildSize: 0.7,
      builder: (BuildContext context, ScrollController scrollController) {
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) => true,
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.background,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.onBackground.withOpacity(0.1),
                  blurRadius: 10.0,
                  spreadRadius: 5.0,
                ),
              ],
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colorScheme.onBackground.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                _buildDropdownHeader(colorScheme),
                if (_isDropdownExpanded) _buildHorizontalScroller(colorScheme),
                Expanded(
                  child: _buildSubscreen(scrollController),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropdownHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _isDropdownExpanded = !_isDropdownExpanded;
                // Refresh groups when expanding the dropdown
                if (_isDropdownExpanded) {
                  _groupsBloc.add(RefreshGroups());
                  _groupsBloc.add(LoadGroups()); // Double-load to ensure update
                }
              });
            },
            child: Row(
              children: [
                Text(
                  _selectedLabel,
                  style: TextStyle(
                    fontSize: 18,
                    color: colorScheme.onBackground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(
                  _isDropdownExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: colorScheme.onBackground,
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.add, color: colorScheme.onBackground),
                onPressed: () => _showAddFriendModal(context),
              ),
              IconButton(
                icon: Icon(Icons.qr_code, color: colorScheme.onBackground),
                onPressed: () => _showProfileModal(context),
              ),
              Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_outlined,
                        color: colorScheme.onBackground),
                    onPressed: () => _showInvitesModal(context),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Consumer<SyncManager>(
                      builder: (context, syncManager, child) {
                        int inviteCount = syncManager.totalInvites;
                        if (inviteCount > 0) {
                          return Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$inviteCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalScroller(ColorScheme colorScheme) {
    return BlocBuilder<GroupsBloc, GroupsState>(
      builder: (context, groupsState) {
        return FutureBuilder<String?>(
          future: _userService.getMyUserId(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final userId = userSnapshot.data;
            if (userId == null) {
              return const SizedBox(
                height: 100,
                child: Center(child: Text('User ID not found')),
              );
            }


            final groups = (groupsState is GroupsLoaded)
                ? groupsState.groups
                : <GridRoom.Room>[];

            return SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const AlwaysScrollableScrollPhysics(),
                primary: false,
                children: [
                  _buildContactOption(colorScheme, userId),
                  ...groups.map((room) => _buildGroupOption(colorScheme, room)),
                  // Show a subtle loading indicator at the end if loading
                  if (groupsState is GroupsLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContactOption(ColorScheme colorScheme, String userId) {
    final isSelected = _selectedLabel == 'My Contacts';

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedOption = SubscreenOption.contacts;
          _selectedLabel = 'My Contacts';
          _isDropdownExpanded = false;
          Provider.of<SelectedSubscreenProvider>(context, listen: false)
              .setSelectedSubscreen('contacts');
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: isSelected
                  ? colorScheme.primary
                  : colorScheme.primary.withOpacity(0.2),
              child: RandomAvatar(
                localpart(userId),
                height: 60,
                width: 60,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'My Contacts',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onBackground,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupOption(ColorScheme colorScheme, GridRoom.Room room) {
    final parts = room.name.split(':');
    print('Room name parts: $parts');
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
            Provider.of<SelectedSubscreenProvider>(context, listen: false)
                .setSelectedSubscreen('group:${room.roomId}');
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: Column(
            children: [
              Stack(
                children: [
                  TriangleAvatars(userIds: room.members),
                  if (room.expirationTimestamp > 0)  // Only show bubble if not infinite
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,  // Always primary color when shown
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          remainingTimeStr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                groupName,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onBackground,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
        return GroupsSubscreen(scrollController: scrollController);
      case SubscreenOption.groupDetails:
        if (_selectedRoom != null) {
          return GroupDetailsSubscreen(
            roomService: _roomService,
            userService: _userService,
            userRepository: _userRepository,
            scrollController: scrollController,
            room: _selectedRoom!,
            onGroupLeft: _navigateToContacts,
          );
        }
        return const Center(child: Text('No group selected'));
      case SubscreenOption.contacts:
      default:
        return ContactsSubscreen(
          roomService: _roomService,
          userRepository: _userRepository,
          scrollController: scrollController,
        );
    }
  }

  Future<void> _navigateToContacts() async {
    setState(() {
      _selectedOption = SubscreenOption.contacts;
      _selectedLabel = 'My Contacts';
      _isDropdownExpanded = false;
      Provider.of<SelectedSubscreenProvider>(context, listen: false)
          .setSelectedSubscreen('contacts');
    });
  }

  // In MapScrollWindow class:
  void _showAddFriendModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
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
    var theme = Theme.of(context).colorScheme;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: theme.surface,
        shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Padding(
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