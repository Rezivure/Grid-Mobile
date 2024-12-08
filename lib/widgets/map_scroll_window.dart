// map_scroll_window.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/widgets/profile_modal.dart'; // Import the profile modal

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
import 'package:grid_frontend/repositories/user_keys_repository.dart';

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
  late final UserKeysRepository _userKeysRepository;

  SubscreenOption _selectedOption = SubscreenOption.contacts;
  bool _isDropdownExpanded = false;
  String _selectedLabel = 'My Contacts';
  Room? _selectedRoom;

  final DraggableScrollableController _scrollableController =
  DraggableScrollableController();

  Future<List<Map<String, dynamic>>>? _groupRoomsFuture;

  @override
  void initState() {
    super.initState();
    // Fetching all services from Provider
    _roomService = context.read<RoomService>();
    _userService = context.read<UserService>();
    _locationRepository = context.read<LocationRepository>();
    _userKeysRepository = context.read<UserKeysRepository>();

    // Set the selected subscreen to 'contacts' in SelectedSubscreenProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SelectedSubscreenProvider>(context, listen: false)
          .setSelectedSubscreen('contacts');
    });
  }

  Future<List<Map<String, dynamic>>> _fetchGroupRooms() async {
    return await _roomService.getGroupRooms();
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
          onInviteHandled: _navigateToContacts, // Refresh invites when handled
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
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              // Move the sheet in sync with the user's finger movement (1:1)
              _scrollableController.jumpTo(
                _scrollableController.size - details.primaryDelta! / 800,
              );
            },
            behavior: HitTestBehavior.translucent, // Allows gesture propagation
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
                  _buildDropdownHeader(colorScheme, context),
                  if (_isDropdownExpanded) _buildHorizontalScroller(colorScheme),
                  Expanded(
                    child: _buildSubscreen(scrollController),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropdownHeader(ColorScheme colorScheme, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _isDropdownExpanded = !_isDropdownExpanded;
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
                onPressed: () {
                  _showAddFriendModal(context);
                },
              ),
              IconButton(
                icon: Icon(Icons.qr_code, color: colorScheme.onBackground),
                onPressed: () {
                  _showProfileModal(context);
                },
              ),
              Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_outlined,
                        color: colorScheme.onBackground),
                    onPressed: () {
                      _showInvitesModal(context);
                    },
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
                        } else {
                          return const SizedBox();
                        }
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
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchGroupRooms(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          return const SizedBox(
            height: 100,
            child: Center(child: Text('Error loading groups')),
          );
        } else {
          final groupRooms = snapshot.data ?? [];

          return SizedBox(
            height: 100,
            child: NotificationListener<ScrollNotification>(
              onNotification: (scrollNotification) {
                if (scrollNotification is ScrollStartNotification ||
                    scrollNotification is ScrollUpdateNotification ||
                    scrollNotification is ScrollEndNotification) {
                  return true;
                }
                return false;
              },
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const AlwaysScrollableScrollPhysics(),
                primary: false,
                children: [
                  _buildContactOption(colorScheme),
                  for (var groupRoomData in groupRooms)
                    _buildGroupOption(colorScheme, groupRoomData),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildContactOption(ColorScheme colorScheme) {
    final isSelected = _selectedLabel == 'My Contacts';
    final String userId = _userService.getMyUserId() as String;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedOption = SubscreenOption.contacts;
          _selectedLabel = 'My Contacts';
          _isDropdownExpanded = false;
          // Update SelectedSubscreenProvider
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

  Widget _buildGroupOption(
      ColorScheme colorScheme, Map<String, dynamic> groupRoomData) {
    final Room room = groupRoomData['room'];
    final List<User> participants = groupRoomData['participants'];

    final parts = room.name.split(':');
    if (parts.length >= 5) {
      final expirationStr = parts[2];
      final groupName = parts[3];
      final expirationUnix = int.tryParse(expirationStr) ?? 0;
      final expirationDate =
      DateTime.fromMillisecondsSinceEpoch(expirationUnix * 1000);
      final now = DateTime.now();
      final remainingDuration = expirationDate.difference(now);
      final isExpired = remainingDuration.isNegative;
      final remainingTimeStr = _formatDuration(remainingDuration);

      final userIds = participants
          .map((user) => user.id.split(':')[0].replaceFirst('@', ''))
          .toList();

      final isSelected = _selectedLabel == groupName;

      return GestureDetector(
        onTap: () {
          setState(() {
            _selectedOption = SubscreenOption.groupDetails;
            _selectedLabel = groupName;
            _selectedRoom = room;
            _isDropdownExpanded = false;
            // Update SelectedSubscreenProvider
            Provider.of<SelectedSubscreenProvider>(context, listen: false)
                .setSelectedSubscreen('groupDetails');
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: Column(
            children: [
              Stack(
                children: [
                  TriangleAvatars(userIds: userIds),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isExpired
                            ? colorScheme.primary
                            : colorScheme.secondary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        isExpired ? '∞' : remainingTimeStr,
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
    } else {
      return const SizedBox.shrink();
    }
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
            locationRepository: _locationRepository,
            userKeysRepository: _userKeysRepository,
            scrollController: scrollController,
            room: _selectedRoom!,
            onGroupLeft: _navigateToContacts,
          );
        } else {
          return const Center(child: Text('No group selected'));
        }
      case SubscreenOption.contacts:
      default:
        return ContactsSubscreen(
          locationRepository: _locationRepository,
          roomService: _roomService,
          userKeysRepository: _userKeysRepository,
          userService: _userService,
          scrollController: scrollController,
        );
    }
  }

  Future<void> _navigateToContacts() async {
    setState(() {
      _selectedOption = SubscreenOption.contacts;
      _selectedLabel = 'My Contacts';
      _isDropdownExpanded = false;
      // Update SelectedSubscreenProvider
      Provider.of<SelectedSubscreenProvider>(context, listen: false)
          .setSelectedSubscreen('contacts');
    });
  }

  void _expandScrollWindow() {
    _scrollableController.jumpTo(0.7);
  }

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
        ),
      ),
    );
  }

  void _showProfileModal(BuildContext context) {
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
