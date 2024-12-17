import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
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
import 'package:grid_frontend/utilities/utils.dart';
import '../blocs/contacts/contacts_bloc.dart';
import '../blocs/contacts/contacts_event.dart';
import '../blocs/contacts/contacts_state.dart';
import '../blocs/map/map_bloc.dart';

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
  TextEditingController _searchController = TextEditingController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Initial load
    context.read<ContactsBloc>().add(LoadContacts());

    // Set up periodic refresh
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        context.read<ContactsBloc>().add(RefreshContacts());
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

  void _onSubscreenSelected(String subscreen) {
    Provider.of<SelectedSubscreenProvider>(context, listen: false)
        .setSelectedSubscreen(subscreen);
  }

  void _onSearchChanged() {
    context.read<ContactsBloc>().add(SearchContacts(_searchController.text));
  }

  String _formatLastSeen(String? timestamp) {
    if (timestamp == null || timestamp == 'Offline') {
      return 'Off Grid';
    }

    try {
      final lastSeenDateTime = DateTime.parse(timestamp);
      return timeAgo(lastSeenDateTime);
    } catch (e) {
      print("Error parsing timestamp: $e");
      return 'Off Grid';
    }
  }

  Widget _buildStatusCircle(String lastSeen, ThemeData theme) {
    Color circleColor;

    if (lastSeen == 'off the grid') {
      circleColor = theme.colorScheme.onSurface.withOpacity(0.5); // Grey
    } else if (lastSeen.contains('m ago') || lastSeen.contains('s ago')) {
      circleColor = theme.colorScheme.primary; // Green
    } else if (lastSeen.contains('h ago')) {
      circleColor = Colors.yellow; // Yellow
    } else if (lastSeen.contains('d ago')) {
      circleColor = Colors.red; // Red
    } else {
      circleColor = theme.colorScheme.onSurface.withOpacity(0.5); // Default Grey
    }

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: circleColor,
        shape: BoxShape.circle,
      ),
    );
  }


  List<ContactDisplay> _getContactsWithCurrentLocation(
      List<ContactDisplay> contacts,
      UserLocationProvider locationProvider) {
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
                        String lastSeen = contact.lastSeen;

                        return Slidable(
                          key: ValueKey(contact.userId),
                          endActionPane: ActionPane(
                            motion: const ScrollMotion(),
                            children: [
                              SlidableAction(
                                onPressed: (_) => context
                                    .read<ContactsBloc>()
                                    .add(DeleteContact(contact.userId)),
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                icon: Icons.delete,
                                label: 'Delete',
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
                            subtitle: Row(
                              children: [
                                _buildStatusCircle(lastSeen, theme), // Add the status circle
                                const SizedBox(width: 8), // Spacing between circle and text
                                Text(
                                  lastSeen,
                                  style: TextStyle(color: colorScheme.onSurface),
                                ),
                              ],
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