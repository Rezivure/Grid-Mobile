import 'dart:async';
import 'package:flutter/material.dart';
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
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'user_avatar.dart';
import 'user_avatar_bloc.dart';
import '../blocs/contacts/contacts_bloc.dart';
import '../blocs/contacts/contacts_event.dart';
import '../blocs/contacts/contacts_state.dart';
import '../blocs/avatar/avatar_bloc.dart';
import '../blocs/avatar/avatar_state.dart';
import 'contact_profile_modal.dart';
import 'add_friend_modal.dart';
import 'location_history_modal.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
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
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: ContactProfileModal(contact: contact, roomService: widget.roomService, sharingPreferencesRepo: widget.sharingPreferencesRepository),
      ),
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
          child: BlocListener<AvatarBloc, AvatarState>(
            listenWhen: (previous, current) => previous.updateCounter != current.updateCounter,
            listener: (context, avatarState) {
              // Force rebuild when avatar updates occur
              setState(() {});
            },
            child: BlocConsumer<ContactsBloc, ContactsState>(
              listener: (context, state) {
                // Show snackbar for error states
                if (state is ContactsError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${state.message}'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              },
              builder: (context, state) {
              if (state is ContactsLoading) {
                return _buildLoadingState();
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
                        ? _buildEmptyState(colorScheme)
                        : ListView.builder(
                            controller: widget.scrollController,
                            itemCount: contactsWithLocation.length,
                            padding: const EdgeInsets.all(16.0),
                            itemBuilder: (context, index) {
                              final contact = contactsWithLocation[index];

                              return _buildModernContactCard(contact, colorScheme, theme);

                            },
                          );
                  },
                );
              }

              return const Center(child: Text('No contacts'));
            },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16.0),
      itemCount: 6, // Show 6 skeleton items
      itemBuilder: (context, index) {
        return _buildSkeletonContactCard();
      },
    );
  }

  Widget _buildSkeletonContactCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Skeleton avatar
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Skeleton title
                Container(
                  height: 16,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                // Skeleton subtitle
                Container(
                  height: 12,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return ListView(
      controller: widget.scrollController,
      children: [
        Container(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.people_outline,
                  size: 64,
                  color: colorScheme.primary.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No contacts yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add friends to start sharing your location and see where they are',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.primary.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Open add friends modal
                    _showAddFriendModal(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(
                    Icons.person_add,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: const Text(
                    'Add Your First Contact',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModernContactCard(ContactDisplay contact, ColorScheme colorScheme, ThemeData theme) {
    // Check if using custom homeserver
    final currentHomeserver = widget.roomService.getMyHomeserver();
    final showFullMatrixId = utils.isCustomHomeserver(currentHomeserver);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Provider.of<SelectedUserProvider>(context, listen: false)
              .setSelectedUserId(contact.userId, context);
        },
        onLongPress: () => _showContactMenu(contact),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              // Smaller avatar with status indicator
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.15),
                        width: 1.5,
                      ),
                    ),
                    child: UserAvatarBloc(
                      userId: contact.userId,
                      size: 44,
                    ),
                  ),
                  // Online status indicator
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: _buildStatusDot(contact.lastSeen, colorScheme, membershipStatus: contact.membershipStatus),
                  ),
                ],
              ),
              
              const SizedBox(width: 12),
              
              // Contact information
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Display name
                    Text(
                      contact.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const SizedBox(height: 2),
                    
                    // User ID subtitle - show full matrix ID for custom homeservers
                    Text(
                      showFullMatrixId ? contact.userId : '@${contact.userId.split(':')[0].replaceFirst('@', '')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Status badge on the right
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Use StatusIndicator if we have membership status, otherwise use enhanced status
                  contact.membershipStatus != null
                      ? StatusIndicator(
                          timeAgo: contact.lastSeen,
                          membershipStatus: contact.membershipStatus,
                        )
                      : _buildEnhancedStatusIndicator(contact.lastSeen, colorScheme, theme),
                  // Future: Add geocoding info here
                  // const SizedBox(height: 4),
                  // Text('2.3 km away', style: TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDot(String timeAgo, ColorScheme colorScheme, {String? membershipStatus}) {
    Color statusColor;
    bool isOnline;
    
    // Check for invitation status first
    if (membershipStatus == 'invite') {
      statusColor = Colors.orange;
      isOnline = false;
    } else {
      statusColor = _getStatusColor(timeAgo, colorScheme);
      isOnline = _isRecentlyActive(timeAgo);
    }
    
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.surface,
          width: 2,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: statusColor,
          shape: BoxShape.circle,
        ),
        child: isOnline
            ? Container(
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.circle,
                  color: Colors.transparent,
                  size: 8,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildEnhancedStatusIndicator(String timeAgo, ColorScheme colorScheme, ThemeData theme) {
    Color statusColor = _getStatusColor(timeAgo, colorScheme);
    IconData statusIcon = _getStatusIcon(timeAgo);
    String enhancedText = _getEnhancedStatusText(timeAgo);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: statusColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            size: 12,
            color: statusColor,
          ),
          const SizedBox(width: 4),
          Text(
            enhancedText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String timeAgo, ColorScheme colorScheme) {
    if (timeAgo == 'Just now' || timeAgo.contains('s ago')) {
      return colorScheme.primary; // Use primary green
    } else if (timeAgo.contains('m ago') && !timeAgo.contains('h')) {
      // Extract minutes to check if over 10 minutes
      final minutesMatch = RegExp(r'(\d+)m ago').firstMatch(timeAgo);
      if (minutesMatch != null) {
        final minutes = int.parse(minutesMatch.group(1)!);
        return minutes <= 10 ? colorScheme.primary : Colors.orange;
      }
      return colorScheme.primary;
    } else if (timeAgo.contains('h ago')) {
      return Colors.orange;
    } else if (timeAgo.contains('d ago')) {
      return Colors.red;
    } else {
      return colorScheme.onSurface.withOpacity(0.4);
    }
  }

  IconData _getStatusIcon(String timeAgo) {
    if (timeAgo == 'Just now' || timeAgo.contains('s ago')) {
      return Icons.circle;
    } else if (timeAgo.contains('m ago') && !timeAgo.contains('h')) {
      return Icons.circle;
    } else if (timeAgo.contains('h ago')) {
      return Icons.schedule;
    } else if (timeAgo.contains('d ago')) {
      return Icons.access_time;
    } else {
      return Icons.circle_outlined;
    }
  }

  String _getEnhancedStatusText(String timeAgo) {
    if (timeAgo == 'Just now') {
      return 'Active now';
    } else if (timeAgo.contains('s ago')) {
      return 'Active now';
    } else if (timeAgo.contains('m ago') && !timeAgo.contains('h')) {
      return timeAgo;
    } else if (timeAgo.contains('h ago')) {
      return timeAgo;
    } else if (timeAgo.contains('d ago')) {
      return timeAgo;
    } else {
      return 'Offline';
    }
  }

  bool _isRecentlyActive(String timeAgo) {
    if (timeAgo == 'Just now' || timeAgo.contains('s ago')) {
      return true;
    }
    if (timeAgo.contains('m ago') && !timeAgo.contains('h')) {
      final minutesMatch = RegExp(r'(\d+)m ago').firstMatch(timeAgo);
      if (minutesMatch != null) {
        final minutes = int.parse(minutesMatch.group(1)!);
        return minutes <= 10; // Only consider active if 10 minutes or less
      }
    }
    return false;
  }

  void _showAddFriendModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: AddFriendModal(
          roomService: widget.roomService,
          userService: Provider.of<UserService>(context, listen: false),
          groupsBloc: context.read<GroupsBloc>(),
          onGroupCreated: () {
            // Refresh contacts when a new group is created
            context.read<ContactsBloc>().add(LoadContacts());
          },
          onContactAdded: () {
            // Trigger immediate refresh - sync manager will handle the rest
            context.read<ContactsBloc>().add(RefreshContacts());
          },
        ),
      ),
    );
  }

  void _showContactMenu(ContactDisplay contact) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Check if using custom homeserver
    final currentHomeserver = widget.roomService.getMyHomeserver();
    final showFullMatrixId = utils.isCustomHomeserver(currentHomeserver);
    
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
              // Contact info header
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
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: colorScheme.primary.withOpacity(0.1),
                      child: UserAvatarBloc(
                        userId: contact.userId,
                        size: 40,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contact.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            showFullMatrixId ? contact.userId : '@${contact.userId.split(':')[0].replaceFirst('@', '')}',
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
              
              // Menu options
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.person,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  'View Profile',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showOptionsDialog(contact);
                },
              ),
              
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
                  _showLocationHistory(contact);
                },
              ),
              
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Remove Contact',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(contact);
                },
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(ContactDisplay contact) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Remove Contact',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove "${contact.displayName}" from your contacts? This action cannot be undone.',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.8),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                final contactName = contact.displayName;
                
                // Send delete event
                context.read<ContactsBloc>().add(DeleteContact(contact.userId));
                
                // Show immediate feedback - assume success unless error occurs
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Removing $contactName from contacts...'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Remove',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  
  void _showLocationHistory(ContactDisplay contact) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return LocationHistoryModal(
          userId: contact.userId,
          userName: contact.displayName,
          avatarUrl: contact.avatarUrl,
        );
      },
    );
  }
}