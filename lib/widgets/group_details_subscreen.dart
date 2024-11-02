import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/providers/room_provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:latlong2/latlong.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'add_group_member_modal.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/widgets/user_keys_modal.dart';

class GroupDetailsSubscreen extends StatefulWidget {
  final ScrollController scrollController;
  final Room room;
  final VoidCallback onGroupLeft;

  GroupDetailsSubscreen({
    required this.scrollController,
    required this.room,
    required this.onGroupLeft,
  });

  @override
  _GroupDetailsSubscreenState createState() => _GroupDetailsSubscreenState();
}

class _GroupDetailsSubscreenState extends State<GroupDetailsSubscreen> {
  bool _isLeaving = false;
  bool _isProcessing = false;
  TextEditingController _searchController = TextEditingController();
  List<User> _filteredParticipants = [];
  late Client _client;
  Map<String, bool> _approvedKeysStatus = {};

  Timer? _timer;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _client = Provider.of<RoomProvider>(context, listen: false).client;
    _filteredParticipants = _getFilteredParticipants();
    _searchController.addListener(_filterParticipants);
    _startAutoSync();
    _fetchApprovedKeysStatus();

    // Set the selected subscreen to the current group
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSubscreenSelected('group:${widget.room.id}');
    });
  }

  Future<void> _fetchApprovedKeysStatus() async {
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    Map<String, bool> tempApprovedKeysStatus = {};

    for (var user in _filteredParticipants) {
      bool? status = await databaseService.getApprovedKeys(user.id);
      if (status != null) {
        // Only add users to the map if the status is not null
        tempApprovedKeysStatus[user.id] = status;
      }
    }

    setState(() {
      _approvedKeysStatus = tempApprovedKeysStatus;
    });
  }



  // NEW: Override didUpdateWidget to handle updates when widget.room changes
  @override
  void didUpdateWidget(GroupDetailsSubscreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      // The room has changed
      setState(() {
        _filteredParticipants = _getFilteredParticipants();
        _searchController.text = ''; // Clear the search field
      });

      // Update the selected subscreen
      _onSubscreenSelected('group:${widget.room.id}');

      // Restart the auto-sync timer
      _timer?.cancel();
      _startAutoSync();
    }
  }

  void _startAutoSync() {
    _timer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() {
          _isSyncing = true;
        });
        _refreshParticipants();
        Future.delayed(Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _isSyncing = false;
            });
          }
        });
      }
    });
  }

  void _refreshParticipants() {
    setState(() {
      _filteredParticipants = _getFilteredParticipants();
    });
    // Fetch and update user locations
    fetchAndUpdateUserLocations('group:${widget.room.id}');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  List<User> _getFilteredParticipants() {
    final searchText = _searchController.text.toLowerCase();
    return widget.room
        .getParticipants()
        .where((user) =>
    user.id != _client.userID &&
        (user.displayName ?? user.id).toLowerCase().contains(searchText))
        .toList();
  }

  void _filterParticipants() {
    setState(() {
      _filteredParticipants = _getFilteredParticipants();
    });
  }

  void _onSubscreenSelected(String subscreen) {
    Provider.of<SelectedSubscreenProvider>(context, listen: false)
        .setSelectedSubscreen(subscreen);
    // Fetch and update user locations for the new subscreen
    fetchAndUpdateUserLocations(subscreen);
  }

  Future<void> fetchAndUpdateUserLocations(String subscreen) async {
    // Fetch the list of users in the group
    List<User> users = widget.room.getParticipants();

    // Fetch the locations of these users
    List<UserLocation> locations = await getUserLocations(users);

    // Update the UserLocationProvider
    Provider.of<UserLocationProvider>(context, listen: false)
        .updateUserLocations(subscreen, locations);
  }


  Future<List<UserLocation>> getUserLocations(List<User> users) async {
    List<UserLocation> locations = [];

    final databaseService = Provider.of<DatabaseService>(context, listen: false);

    for (var user in users) {
      final userLocationData = await databaseService.getUserLocationById(user.id);

      if (userLocationData != null) {
        locations.add(UserLocation(
          userId: userLocationData.userId,
          latitude: userLocationData.latitude,
          longitude: userLocationData.longitude,
          timestamp: userLocationData.timestamp,
          iv: userLocationData.iv,
        ));
      } else {
        print('No location data available for user: ${user.id}');
      }
    }

    return locations;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        CustomSearchBar(
          controller: _searchController,
          hintText: 'Search Members',
        ),
        if (_isSyncing)
          Container(
            padding: EdgeInsets.all(8.0),
            child: Text(
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
                      future: _getLastSeen(user), // This will fetch the last seen time
                      builder: (context, snapshot) {
                        final membership = user.membership; // Fetch the membership status
                        final lastSeen = snapshot.data ?? 'Unknown';

                        String subtitleText;
                        TextStyle subtitleStyle;

                        if (membership == Membership.invite) {
                          // If the user is invited, display "Invited" in orange
                          subtitleText = 'Invitation Sent';
                          subtitleStyle = TextStyle(color: Colors.orange);
                        } else {
                          // Otherwise, display the last seen time
                          subtitleText = 'Last seen: $lastSeen';
                          subtitleStyle = TextStyle(color: Theme.of(context).colorScheme.onSurface);
                        }

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
                                          userId: user.id,
                                          approvedKeys: _approvedKeysStatus[user.id] ?? false,
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
                                      color: (_approvedKeysStatus[user.id] ?? false)
                                          ? Colors.green.withOpacity(0.8)
                                          : (_approvedKeysStatus.containsKey(user.id)
                                          ? Colors.red.withOpacity(0.8)
                                          : Colors.grey.withOpacity(0.8)), // Grey for unknown status
                                    ),
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      (_approvedKeysStatus[user.id] ?? false)
                                          ? Icons.lock
                                          : (_approvedKeysStatus.containsKey(user.id)
                                          ? Icons.lock_open
                                          : Icons.help_rounded), // Grey question mark for unknown
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
                            style: TextStyle(color: Theme.of(context).colorScheme.onBackground),
                          ),
                          subtitle: Text(
                            subtitleText,
                            style: subtitleStyle,
                          ),
                          onTap: () {
                            final selectedUserProvider =
                            Provider.of<SelectedUserProvider>(context, listen: false);
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
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0)
                      .copyWith(top: 20.0),
                  child: Column(
                    children: [
                      // Add Member Button
                      SizedBox(
                        width: 180, // Set narrower width for the button
                        child: ElevatedButton(
                          onPressed: _isProcessing
                              ? null
                              : () => _showAddGroupMemberModal(),
                          child: Text('Add Member'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.onSurface,
                            foregroundColor: colorScheme.surface,
                            side: BorderSide(color: colorScheme.onSurface),
                            minimumSize: Size(150, 40), // Narrower button
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      // Leave Group Button
                      SizedBox(
                        width: 180, // Set narrower width for the button
                        child: ElevatedButton(
                          onPressed:
                          _isLeaving ? null : _showLeaveConfirmationDialog,
                          child: _isLeaving
                              ? CircularProgressIndicator(color: Colors.red)
                              : Text('Leave Group'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.red,
                            side: BorderSide(color: Colors.red),
                            minimumSize: Size(150, 40), // Narrower button
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

  // Show the AddGroupMemberModal
  void _showAddGroupMemberModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return AddGroupMemberModal(roomId: widget.room.id); // Pass the roomId
      },
    );
  }

  Future<void> _showLeaveConfirmationDialog() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Leave Group'),
          content: Text('Are you sure you want to leave this group?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text('Leave'),
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
      final roomProvider = Provider.of<RoomProvider>(context, listen: false);
      await roomProvider.leaveGroup(widget.room);

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

  Future<String> _getLastSeen(User user) async {
    final lastSeen = await Provider.of<RoomProvider>(context, listen: false)
        .getLastSeenTime(user);
    return lastSeen;
  }
}
