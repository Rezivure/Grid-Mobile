import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'add_group_member_modal.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/widgets/user_keys_modal.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/services/user_service.dart';

class GroupDetailsSubscreen extends StatefulWidget {
  final UserService userService;
  final RoomService roomService;
  final UserKeysRepository userKeysRepository;
  final ScrollController scrollController;
  final Room room;
  final VoidCallback onGroupLeft;

  GroupDetailsSubscreen({
    required this.scrollController,
    required this.room,
    required this.onGroupLeft,
    required this.roomService,
    required this.userKeysRepository,
    required this.userService,
  });

  @override
  _GroupDetailsSubscreenState createState() => _GroupDetailsSubscreenState();
}

class _GroupDetailsSubscreenState extends State<GroupDetailsSubscreen> {
  bool _isLeaving = false;
  bool _isProcessing = false;
  TextEditingController _searchController = TextEditingController();
  List<User> _filteredParticipants = [];
  Map<String, bool> _approvedKeysStatus = {};

  Timer? _timer;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _filteredParticipants = _getFilteredParticipants();
    _searchController.addListener(_filterParticipants);
    _startAutoSync();
    _fetchApprovedKeysStatus();

    // Set the selected subscreen to the current group
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSubscreenSelected('group:${widget.room.id}');
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(GroupDetailsSubscreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      // The room has changed, refresh participants and reset search
      setState(() {
        _filteredParticipants = _getFilteredParticipants();
        _searchController.text = '';
      });

      _onSubscreenSelected('group:${widget.room.id}');
      _timer?.cancel();
      _startAutoSync();
    }
  }

  void _onSubscreenSelected(String subscreen) {
    Provider.of<SelectedSubscreenProvider>(context, listen: false)
        .setSelectedSubscreen(subscreen);
    // No direct fetching of locations needed, the UserLocationProvider is reactive
  }

  void _startAutoSync() {
    // Periodic sync as a fallback for participants list (not needed for location)
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() {
          _isSyncing = true;
        });
        _refreshParticipants();
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _isSyncing = false;
            });
          }
        });
      }
    });
  }

  Future<void> _refreshParticipants() async {
    // Just refresh participants list filtering
    setState(() {
      _filteredParticipants = _getFilteredParticipants();
    });
    // No need to manually fetch locations; they update via UserLocationProvider
  }

  Future<void> _fetchApprovedKeysStatus() async {
    Map<String, bool> tempApprovedKeysStatus = {};
    for (var user in _filteredParticipants) {
      bool? status = await widget.userKeysRepository.getApprovedKeys(user.id);
      if (status != null) {
        tempApprovedKeysStatus[user.id] = status;
      }
    }
    setState(() {
      _approvedKeysStatus = tempApprovedKeysStatus;
    });
  }

  List<User> _getFilteredParticipants() {
    final searchText = _searchController.text.toLowerCase();
    return widget.room
        .getParticipants()
        .where((user) =>
    user.id != widget.room.client?.userID &&
        (user.displayName ?? user.id).toLowerCase().contains(searchText))
        .toList();
  }

  void _filterParticipants() {
    setState(() {
      _filteredParticipants = _getFilteredParticipants();
    });
  }

  Future<void> _showLeaveConfirmationDialog() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Leave Group'),
          content: const Text('Are you sure you want to leave this group?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Leave'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
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
      await widget.roomService.leaveRoom(widget.room.id);
      widget.onGroupLeft();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error leaving group: $e')),
      );
    } finally {
      setState(() {
        _isLeaving = false;
      });
    }
  }

  // Retrieve a user's last seen time
  Future<String> _getLastSeen(User user) async {
    final lastSeen = await widget.userService.getLastSeenTime(user.id);
    return lastSeen;
  }

  void _showAddGroupMemberModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return AddGroupMemberModal(
          roomId: widget.room.id,
          userService: widget.userService,
          roomService: widget.roomService,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get all user locations from the provider
    final userLocations = Provider.of<UserLocationProvider>(context).getAllUserLocations();

    return Column(
      children: [
        CustomSearchBar(
          controller: _searchController,
          hintText: 'Search Members',
        ),
        if (_isSyncing)
          Container(
            padding: const EdgeInsets.all(8.0),
            child: const Text(
              'Syncing...',
              style: TextStyle(color: Colors.black),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            padding: EdgeInsets.zero,
            itemCount: _filteredParticipants.length + 1,
            itemBuilder: (context, index) {
              if (index < _filteredParticipants.length) {
                final user = _filteredParticipants[index];

                return Column(
                  children: [
                    FutureBuilder<String>(
                      future: _getLastSeen(user),
                      builder: (context, snapshot) {
                        final lastSeen = snapshot.data ?? 'Unknown';
                        final membership = user.membership;

                        // Find the user's latest location from the provider
                        final userLocation = userLocations.firstWhere(
                              (loc) => loc.userId == user.id,
                          orElse: () => UserLocation(
                            userId: user.id,
                            latitude: 0.0,
                            longitude: 0.0,
                            timestamp: 'Loading...',
                            iv: '',
                          ),
                        );

                        String subtitleText;
                        TextStyle subtitleStyle = TextStyle(color: colorScheme.onSurface);

                        if (membership == Membership.invite) {
                          subtitleText = 'Invitation Sent';
                          subtitleStyle = const TextStyle(color: Colors.orange);
                        } else {
                          // Display last seen and location info together
                          subtitleText = 'Last seen: $lastSeen | Loc: ${userLocation.latitude}, ${userLocation.longitude}';
                        }

                        bool approvedKeys = _approvedKeysStatus[user.id] ?? false;

                        return ListTile(
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                child: RandomAvatar(
                                  user.id.split(':')[0].replaceFirst('@', ''),
                                  height: 60,
                                  width: 60,
                                ),
                                backgroundColor: colorScheme.primary.withOpacity(0.2),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () async {
                                    if (_approvedKeysStatus.containsKey(user.id)) {
                                      bool? result = await showDialog<bool>(
                                        context: context,
                                        builder: (_) => UserKeysModal(
                                          userService: widget.userService,
                                          userKeysRepository: widget.userKeysRepository,
                                          userId: user.id,
                                          approvedKeys: approvedKeys,
                                        ),
                                      );
                                      if (result == true) {
                                        setState(() {
                                          _approvedKeysStatus[user.id] = true;
                                        });
                                      }
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: approvedKeys
                                          ? Colors.green.withOpacity(0.8)
                                          : (_approvedKeysStatus.containsKey(user.id)
                                          ? Colors.red.withOpacity(0.8)
                                          : Colors.grey.withOpacity(0.8)),
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      approvedKeys
                                          ? Icons.lock
                                          : (_approvedKeysStatus.containsKey(user.id)
                                          ? Icons.lock_open
                                          : Icons.help_rounded),
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          title: Text(
                            user.displayName ?? user.id,
                            style: TextStyle(color: colorScheme.onBackground),
                          ),
                          subtitle: Text(
                            subtitleText,
                            style: subtitleStyle,
                          ),
                          onTap: () {
                            final selectedUserProvider = Provider.of<SelectedUserProvider>(context, listen: false);
                            selectedUserProvider.setSelectedUserId(user.id);
                            print('Group member selected: ${user.id}');
                          },
                        );
                      },
                    ),
                    if (index != _filteredParticipants.length - 1)
                      Divider(
                        thickness: 1,
                        color: colorScheme.onSurface.withOpacity(0.1),
                        indent: 20,
                        endIndent: 20,
                      ),
                  ],
                );
              } else {
                // The last item shows buttons
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0).copyWith(top: 20.0),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 180,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : _showAddGroupMemberModal,
                          child: const Text('Add Member'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.onSurface,
                            foregroundColor: colorScheme.surface,
                            side: BorderSide(color: colorScheme.onSurface),
                            minimumSize: const Size(150, 40),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 180,
                        child: ElevatedButton(
                          onPressed: _isLeaving ? null : _showLeaveConfirmationDialog,
                          child: _isLeaving
                              ? const CircularProgressIndicator(color: Colors.red)
                              : const Text('Leave Group'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            minimumSize: const Size(150, 40),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
