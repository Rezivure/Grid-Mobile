import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:grid_frontend/widgets/status_indictator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/utilities/time_ago_formatter.dart';
import '../blocs/contacts/contacts_bloc.dart';
import '../blocs/contacts/contacts_event.dart';
import '../blocs/contacts/contacts_state.dart';
import 'contact_profile_modal.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';

class ContactsSubscreen extends StatefulWidget {
  final ScrollController scrollController;
  final RoomService roomService;
  final UserRepository userRepository;
  final SharingPreferencesRepository sharingPreferencesRepository;

  const ContactsSubscreen({
    required this.scrollController,
    required this.roomService,
    required this.userRepository,
    required this.sharingPreferencesRepository,
    Key? key,
  }) : super(key: key);

  @override
  ContactsSubscreenState createState() => ContactsSubscreenState();
}

class ContactsSubscreenState extends State<ContactsSubscreen> {
  TextEditingController _searchController = TextEditingController();
  Timer? _timer;
  bool _isRefreshing = false;


  @override
  void initState() {
    super.initState();
    context.read<ContactsBloc>().add(LoadContacts());

    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_isRefreshing) {
        _refreshContacts();
      }
    });

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

  Future<void> _refreshContacts() async {
    _isRefreshing = true;
    try {
      context.read<ContactsBloc>().add(RefreshContacts());
      // Wait a short duration to prevent debounce
      await Future.delayed(const Duration(seconds: 2));
    } finally {
      _isRefreshing = false;
    }
  }

  void _onSubscreenSelected(String subscreen) {
    Provider.of<SelectedSubscreenProvider>(context, listen: false)
        .setSelectedSubscreen(subscreen);
  }

  void _onSearchChanged() {
    context.read<ContactsBloc>().add(SearchContacts(_searchController.text));
  }

  void _showOptionsDialog(ContactDisplay contact) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ContactProfileModal(contact: contact, roomService: widget.roomService, sharingPreferencesRepo: widget.sharingPreferencesRepository),
    );
  }

  List<ContactDisplay> _getContactsWithCurrentLocation(
      List<ContactDisplay> contacts,
      UserLocationProvider locationProvider) {
    return contacts.map((contact) {
      final lastSeenTimestamp = locationProvider.getLastSeen(contact.userId);
      final formattedLastSeen = TimeAgoFormatter.format(lastSeenTimestamp);

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
        Expanded(
          child: BlocBuilder<ContactsBloc, ContactsState>(
            builder: (context, state) {
              if (state is ContactsLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is ContactsError) {
                return Center(child: Text('Error: ${state.message}'));
              }

              if (state is ContactsLoaded) {
                return Consumer<UserLocationProvider>(
                  builder: (context, locationProvider, child) {
                    final contactsWithLocation = _getContactsWithCurrentLocation(
                      state.contacts,
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

                        return Slidable(
                          key: ValueKey(contact.userId),
                          // Swiping right (startActionPane) for "Options"
                          startActionPane: ActionPane(
                            motion: const ScrollMotion(),
                            extentRatio: 0.25,
                            children: [
                              CustomSlidableAction(  // Change to CustomSlidableAction
                                onPressed: (_) {
                                  _showOptionsDialog(contact);
                                },
                                backgroundColor: theme.colorScheme.primary,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person, color: Colors.white), // Explicitly set icon color
                                    const SizedBox(height: 4),
                                    Text('Profile',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                                flex: 1,
                              ),
                            ],
                          ),
                          // Swiping left (endActionPane) for "Delete"
                          endActionPane: ActionPane(
                            motion: const ScrollMotion(),
                            extentRatio: 0.25,
                            children: [
                              CustomSlidableAction(
                                onPressed: (_) {
                                  context.read<ContactsBloc>().add(DeleteContact(contact.userId));
                                },
                                backgroundColor: Colors.red,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.delete, color: Colors.white),
                                    const SizedBox(height: 4),
                                    Text('Delete',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                                flex: 1,
                              ),
                            ],
                          ),
                          child: ListTile(
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
                            subtitle: StatusIndicator(
                              timeAgo: contact.lastSeen,
                              // TODO: add membership status for invited contacts
                            ),
                            onTap: () {
                              Provider.of<SelectedUserProvider>(context, listen: false)
                                  .setSelectedUserId(contact.userId, context);
                            },
                          ),
                        );

                      },
                    );
                  },
                );
              }

              return const Center(child: Text('No contacts'));
            },
          ),
        ),
      ],
    );
  }
}