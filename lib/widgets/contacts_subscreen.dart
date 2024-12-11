import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/utilities/utils.dart';

class ContactsSubscreen extends StatefulWidget {
  final ScrollController scrollController;
  final RoomService roomService;
  final UserRepository userRepository;

  const ContactsSubscreen({
    required this.scrollController,
    required this.roomService,
    required this.userRepository,
    Key? key,
  }) : super(key: key);

  @override
  ContactsSubscreenState createState() => ContactsSubscreenState();
}

class ContactsSubscreenState extends State<ContactsSubscreen> {
  List<ContactDisplay> _baseContacts = [];
  List<ContactDisplay> _filteredContacts = [];
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

  void _onSubscreenSelected(String subscreen) {
    Provider.of<SelectedSubscreenProvider>(context, listen: false)
        .setSelectedSubscreen(subscreen);
  }

  Future<void> _initializeContacts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUserId = widget.roomService.getMyUserId();
      final directContacts = await widget.userRepository.getDirectContacts();

      setState(() {
        _baseContacts = directContacts
            .where((contact) => contact.userId != currentUserId)
            .map((contact) => ContactDisplay(
          userId: contact.userId,
          displayName: contact.displayName ?? 'Unknown User',
          avatarUrl: contact.avatarUrl,
          lastSeen: 'Offline',
        ))
            .toList();

        _updateFilteredContacts();
        _isLoading = false;
      });
    } catch (e) {
      print("Error initializing contacts: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateFilteredContacts() {
    String searchQuery = _searchController.text.toLowerCase();
    _filteredContacts = _baseContacts.where((user) {
      String displayName = user.displayName.toLowerCase();
      String userId = user.userId.toLowerCase();
      return displayName.contains(searchQuery) || userId.contains(searchQuery);
    }).toList();
  }

  void _onSearchChanged() {
    setState(() {
      _updateFilteredContacts();
    });
  }

  void _startAutoSync() {
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() {
          print("Syncing UI screen...");
          _isSyncing = true;
        });
        _initializeContacts();
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

  String _formatLastSeen(String? timestamp) {
    if (timestamp == null || timestamp == 'Offline') {
      return 'Offline';
    }

    try {
      final lastSeenDateTime = DateTime.parse(timestamp);
      return timeAgo(lastSeenDateTime);
    } catch (e) {
      print("Error parsing timestamp: $e");
      return 'Offline';
    }
  }

  List<ContactDisplay> _getContactsWithCurrentLocation(
      List<ContactDisplay> contacts,
      UserLocationProvider locationProvider
      ) {
    return contacts.map((contact) {
      final lastSeenTimestamp = locationProvider.getLastSeen(contact.userId);
      final formattedLastSeen = _formatLastSeen(lastSeenTimestamp);

      return ContactDisplay(
        userId: contact.userId,
        displayName: contact.displayName,
        avatarUrl: contact.avatarUrl,
        lastSeen: formattedLastSeen,
      );
    }).toList();
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
              : Consumer<UserLocationProvider>(
            builder: (context, locationProvider, child) {
              final contactsWithLocation = _getContactsWithCurrentLocation(
                _filteredContacts,
                locationProvider,
              );

              return contactsWithLocation.isEmpty
                  ? ListView(
                controller: widget.scrollController,
                children: const [
                  Center(child: Text('No contacts found')),
                ],
              )
                  : ListView.builder(
                controller: widget.scrollController,
                itemCount: contactsWithLocation.length,
                padding: const EdgeInsets.only(top: 8.0),
                itemBuilder: (context, index) {
                  final contact = contactsWithLocation[index];
                  String lastSeen = contact.lastSeen;

                  return ListTile(
                    leading: CircleAvatar(
                      radius: 30,
                      child: RandomAvatar(
                        contact.userId.split(':')[0].replaceFirst('@', ''),
                        height: 60,
                        width: 60,
                      ),
                      backgroundColor: colorScheme.primary.withOpacity(0.2),
                    ),
                    title: Text(
                      contact.displayName,
                      style: TextStyle(color: colorScheme.onBackground),
                    ),
                    subtitle: Text(
                      lastSeen,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    onTap: () {
                      final selectedUserProvider =
                      Provider.of<SelectedUserProvider>(context, listen: false);
                      selectedUserProvider.setSelectedUserId(contact.userId);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}