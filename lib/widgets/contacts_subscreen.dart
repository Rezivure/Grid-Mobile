// lib/widgets/contacts_subscreen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/providers/room_provider.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/services/database_service.dart';

class ContactsSubscreen extends StatefulWidget {
  final ScrollController scrollController;

  ContactsSubscreen({required this.scrollController, Key? key})
      : super(key: key);

  @override
  ContactsSubscreenState createState() => ContactsSubscreenState();
}

class ContactsSubscreenState extends State<ContactsSubscreen> {
  List<User> _contacts = [];
  List<User> _filteredContacts = [];
  Timer? _timer;
  bool _isSyncing = false;
  bool _isLoading = true;

  Map<String, String> _userRoomMap = {};
  Map<String, Map<String, dynamic>> _userStatusCache = {};

  TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeContacts();
    _startAutoSync();

    // Set the selected subscreen to 'contacts'
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSubscreenSelected('contacts');
    });

    // Add listener to search controller
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _initializeContacts() async {
    await _fetchContacts();
    await fetchAndUpdateUserLocations('contacts');
  }

  void _startAutoSync() {
    _timer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() {
          _isSyncing = true;
        });
        refreshContacts();
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

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchContacts() async {
    setState(() {
      _isLoading = true;
    });

    var result = await Provider.of<RoomProvider>(context, listen: false)
        .getDirectRooms();

    Map<String, Map<String, dynamic>> userStatusCache = {};

    Map<User, String> userRoomMap = Map<User, String>.from(result['userRoomMap']);
    Map<String, String> tempUserRoomMap = userRoomMap.map<String, String>(
            (User user, String roomId) => MapEntry(user.id, roomId));
    List<User> contacts = result['users'];

    // Fetch status for all contacts
    for (User user in contacts) {
      String lastSeen = await Provider.of<RoomProvider>(context, listen: false)
          .getLastSeenTime(user);
      String? roomId = tempUserRoomMap[user.id];
      bool isInvited = false;

      if (roomId != null) {
        isInvited = await Provider.of<RoomProvider>(context, listen: false)
            .isUserInvited(roomId, user.id);
      }

      // Only add to status cache if the current user is in a joined state or has sent an invite.
      if (isInvited || userRoomMap[user]?.isNotEmpty == true) {
        Map<String, dynamic> status = {'lastSeen': lastSeen, 'isInvited': isInvited};
        userStatusCache[user.id] = status;
      }
    }

    setState(() {
      _userRoomMap = tempUserRoomMap;
      _contacts = contacts;
      _filteredContacts = _contacts;
      _userStatusCache = userStatusCache;
      _isLoading = false;
    });
  }

  Future<void> refreshContacts() async {
    await _fetchContacts();
    await fetchAndUpdateUserLocations('contacts');
  }


  void _onSubscreenSelected(String subscreen) {
    Provider.of<SelectedSubscreenProvider>(context, listen: false)
        .setSelectedSubscreen(subscreen);
  }

  Future<void> fetchAndUpdateUserLocations(String subscreen) async {
    List<UserLocation> locations = await getUserLocations(_contacts);
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
          deviceKeys: userLocationData.deviceKeys,
          iv: userLocationData.iv,
        ));
      } else {
        print('No location data available for user: ${user.id}');
      }
    }

    return locations;
  }


  void _onSearchChanged() {
    String searchQuery = _searchController.text.toLowerCase();
    setState(() {
      _filteredContacts = _contacts.where((user) {
        String displayName = user.displayName?.toLowerCase() ?? '';
        String userId = user.id.toLowerCase();
        return displayName.contains(searchQuery) || userId.contains(searchQuery);
      }).toList();
    });
  }

  void _showRemoveContactDialog(User contact) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Remove Contact'),
          content: Text('Would you like to remove this contact?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Remove'),
              onPressed: () {
                Navigator.of(context).pop();
                _removeContact(contact);
              },
            ),
          ],
        );
      },
    );
  }

  void _removeContact(User contact) async {
    String? roomId = _userRoomMap[contact.id];
    if (roomId != null) {
      bool success = await Provider.of<RoomProvider>(context, listen: false)
          .leaveRoom(roomId);
      if (success) {
        setState(() {
          _contacts.remove(contact);
          _filteredContacts.remove(contact);
          _userRoomMap.remove(contact.id);
          _userStatusCache.remove(contact.id);
        });
        await fetchAndUpdateUserLocations('contacts');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Contact removed successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove contact')),
        );
      }
    } else {
      print('No room ID found for contact: ${contact.id}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove contact: No room ID found')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        CustomSearchBar(
          controller: _searchController,
          hintText: 'Search Contacts',
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
          child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : _filteredContacts.isEmpty
              ? ListView(
            controller: widget.scrollController,
            children: [
              Center(child: Text('No contacts found')),
            ],
          )
              : ListView.builder(
            controller: widget.scrollController,
            itemCount: _filteredContacts.length,
            padding: EdgeInsets.only(top: 8.0),
            itemBuilder: (context, index) {
              final contact = _filteredContacts[index];
              final data = _userStatusCache[contact.id];

              String subtitleText;
              TextStyle subtitleStyle =
              TextStyle(color: colorScheme.onSurface);

              if (data != null) {
                final lastSeen = data['lastSeen'] as String;
                final isInvited = data['isInvited'] as bool;

                if (isInvited) {
                  subtitleText = 'Invitation Sent';
                  subtitleStyle = TextStyle(color: Colors.orange);
                } else {
                  subtitleText = 'Last seen: $lastSeen';
                }
              } else {
                subtitleText = 'Loading...';
                subtitleStyle = TextStyle(color: Colors.grey);
              }

              return Column(
                children: [
                  Slidable(
                    key: ValueKey(contact.id),
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.15,
                      children: [
                        SlidableAction(
                          onPressed: (context) {
                            _showRemoveContactDialog(contact);
                          },
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          icon: Icons.delete,
                          label: '',
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 30,
                        child: RandomAvatar(
                          contact.id.split(':')[0].replaceFirst('@', ''),
                          height: 60,
                          width: 60,
                        ),
                        backgroundColor:
                        colorScheme.primary.withOpacity(0.2),
                      ),
                      title: Text(
                        contact.displayName ?? contact.id,
                        style: TextStyle(color: colorScheme.onBackground),
                      ),
                      subtitle: Text(
                        subtitleText,
                        style: subtitleStyle,
                      ),
                      onTap: () {
                        final selectedUserProvider =
                        Provider.of<SelectedUserProvider>(context,
                            listen: false);
                        selectedUserProvider
                            .setSelectedUserId(contact.id);
                        print('Contact selected: ${contact.id}');
                      },
                    ),
                  ),
                  Divider(
                    thickness: 1,
                    color: colorScheme.onSurface.withOpacity(0.1),
                    indent: 20,
                    endIndent: 20,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
