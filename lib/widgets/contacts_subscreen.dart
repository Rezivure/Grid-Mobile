import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:matrix/matrix.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/utilities/utils.dart';

class ContactsSubscreen extends StatefulWidget {
  final ScrollController scrollController;
  final RoomService roomService;
  final UserService userService;
  final UserKeysRepository userKeysRepository;

  const ContactsSubscreen({
    required this.scrollController,
    required this.roomService,
    required this.userService,
    required this.userKeysRepository,
    Key? key,
  }) : super(key: key);

  @override
  ContactsSubscreenState createState() => ContactsSubscreenState();
}

class ContactsSubscreenState extends State<ContactsSubscreen> {
  List<User> _contacts = [];
  List<User> _filteredContacts = [];
  Map<String, String> _userRoomMap = {};
  Map<String, Map<String, dynamic>> _userStatusCache = {};
  Map<String, bool> _approvedKeysStatus = {};

  TextEditingController _searchController = TextEditingController();
  Timer? _timer;

  bool _isSyncing = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeContacts();
    _startAutoSync();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSubscreenSelected('contacts');
    });

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeContacts() async {
    await _fetchContacts();
    await _fetchApprovedKeysStatus();
    setState(() {}); // Refresh UI after initial load
  }

  void _startAutoSync() {
    // Periodic sync as a fallback
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() {
          _isSyncing = true;
        });
        refreshContacts();
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

  Future<void> refreshContacts() async {
    await _fetchContacts();
    await _fetchApprovedKeysStatus();
    setState(() {}); // Update UI after refresh
  }

  Future<void> _fetchContacts() async {
    setState(() {
      _isLoading = true;
    });

    var result = await widget.roomService.getDirectRooms();

    Map<User, String> userRoomMap = Map<User, String>.from(result['userRoomMap']);
    Map<String, String> tempUserRoomMap =
    userRoomMap.map<String, String>((User user, String roomId) => MapEntry(user.id, roomId));
    List<User> contacts = result['users'];

    Map<String, Map<String, dynamic>> userStatusCache = {};

    // Fetch status for all contacts
    for (User user in contacts) {
      String lastSeen = await widget.userService.getLastSeenTime(user.id);
      String? roomId = tempUserRoomMap[user.id];
      bool isInvited = false;

      if (roomId != null) {
        isInvited = await widget.userService.isUserInvited(roomId, user.id);
      }

      if (isInvited || userRoomMap[user]?.isNotEmpty == true) {
        Map<String, dynamic> status = {
          'lastSeen': lastSeen,
          'isInvited': isInvited,
        };
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

  Future<void> _fetchApprovedKeysStatus() async {
    Map<String, bool> tempApprovedKeysStatus = {};
    for (var user in _contacts) {
      bool? status = await widget.userKeysRepository.getApprovedKeys(user.id);
      if (status != null) {
        tempApprovedKeysStatus[user.id] = status;
      }
    }
    setState(() {
      _approvedKeysStatus = tempApprovedKeysStatus;
    });
  }

  void _onSubscreenSelected(String subscreen) {
    Provider.of<SelectedSubscreenProvider>(context, listen: false).setSelectedSubscreen(subscreen);
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
          title: const Text('Remove Contact'),
          content: const Text('Would you like to remove this contact?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Remove'),
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
      bool success = await widget.roomService.leaveRoom(roomId);
      if (success) {
        setState(() {
          _contacts.remove(contact);
          _filteredContacts.remove(contact);
          _userRoomMap.remove(contact.id);
          _userStatusCache.remove(contact.id);
          _approvedKeysStatus.remove(contact.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact removed successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to remove contact')),
        );
      }
    } else {
      print('No room ID found for contact: ${contact.id}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to remove contact: No room ID found')),
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
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Syncing...',
              style: TextStyle(color: colorScheme.onSurface),
            ),
          ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredContacts.isEmpty
              ? ListView(
            controller: widget.scrollController,
            children: const [
              Center(child: Text('No contacts found')),
            ],
          )
              : ListView.builder(
            controller: widget.scrollController,
            itemCount: _filteredContacts.length,
            padding: const EdgeInsets.only(top: 8.0),
              itemBuilder: (context, index) {
                final contact = _filteredContacts[index];
                final userLocation = Provider.of<UserLocationProvider>(context).getUserLocation(contact.id);

                String subtitleText;
                TextStyle subtitleStyle = TextStyle(color: colorScheme.onSurface);

                if (userLocation != null) {
                  try {
                    final lastSeenDate = DateTime.parse(userLocation.timestamp);
                    final timeAgoString = timeAgo(lastSeenDate);
                    subtitleText = 'Last seen: $timeAgoString';
                  } catch (e) {
                    subtitleText = 'Last seen: Offline';
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
                          backgroundColor: colorScheme.primary.withOpacity(0.2),
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
                          final selectedUserProvider = Provider.of<SelectedUserProvider>(context, listen: false);
                          selectedUserProvider.setSelectedUserId(contact.id);
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
              }
          ),
        ),
      ],
    );
  }
}
