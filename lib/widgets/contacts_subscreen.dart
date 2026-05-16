import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/utilities/time_ago_formatter.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_segmented.dart';
import 'package:grid_frontend/widgets/grid/grid_contact_row.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
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
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

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

class ContactsSubscreenState extends State<ContactsSubscreen> with TickerProviderStateMixin {
  Timer? _timer;
  bool _isRefreshing = false;
  late AnimationController _dotsAnimationController;
  late Animation<int> _dotsAnimation;
  late AnimationController _checkmarkAnimationController;
  late Animation<double> _checkmarkScaleAnimation;
  late Animation<double> _checkmarkFadeAnimation;
  bool _showCheckmark = false;
  bool _syncJustCompleted = false;
  SyncState? _previousSyncState;
  bool _hasShownInitialLoading = false;


  @override
  void initState() {
    super.initState();
    context.read<ContactsBloc>().add(LoadContacts());

    // Initialize animation for syncing dots
    _dotsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _dotsAnimation = IntTween(begin: 0, end: 3).animate(
      CurvedAnimation(
        parent: _dotsAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Initialize checkmark animation
    _checkmarkAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _checkmarkScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _checkmarkAnimationController,
      curve: Curves.elasticOut,
    ));

    _checkmarkFadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _checkmarkAnimationController,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
    ));

    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_isRefreshing) {
        _refreshContacts();
      }
    });


    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSubscreenSelected('contacts');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dotsAnimationController.dispose();
    _checkmarkAnimationController.dispose();
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
    // Create a list with both the formatted time and the actual timestamp for sorting
    final contactsWithTimestamp = contacts.map((contact) {
      final lastSeenTimestamp = locationProvider.getLastSeen(contact.userId);
      final formattedLastSeen = TimeAgoFormatter.format(lastSeenTimestamp);

      return {
        'contact': ContactDisplay(
          userId: contact.userId,
          displayName: contact.displayName,
          avatarUrl: contact.avatarUrl,
          lastSeen: formattedLastSeen,
          membershipStatus: contact.membershipStatus,
        ),
        'timestamp': lastSeenTimestamp,
      };
    }).toList();

    // Sort by timestamp (most recent first)
    contactsWithTimestamp.sort((a, b) {
      final timestampA = a['timestamp'] as String?;
      final timestampB = b['timestamp'] as String?;

      // Handle null timestamps (put them at the end)
      if (timestampA == null && timestampB == null) return 0;
      if (timestampA == null) return 1;
      if (timestampB == null) return -1;

      // Parse and compare timestamps
      try {
        final dateA = DateTime.parse(timestampA);
        final dateB = DateTime.parse(timestampB);
        return dateB.compareTo(dateA); // Descending order (most recent first)
      } catch (e) {
        // If parsing fails, treat as equal
        return 0;
      }
    });

    // Return only the sorted ContactDisplay objects
    return contactsWithTimestamp
        .map((item) => item['contact'] as ContactDisplay)
        .toList();
  }

  // Categorize a contact's section by its time-ago string + membership status.
  // - SHARING NOW: live / recently active (≤ 10 min, no invite)
  // - PAUSED: invitation pending OR loosely active (minutes/hours)
  // - OFFLINE: days/unknown
  _ContactBucket _bucketFor(ContactDisplay c) {
    final time = c.lastSeen;
    if (c.membershipStatus == 'invite') return _ContactBucket.paused;

    if (time == 'Just now' || time.contains('s ago')) {
      return _ContactBucket.sharingNow;
    }
    if (time.contains('m ago') && !time.contains('h')) {
      final m = RegExp(r'(\d+)m ago').firstMatch(time);
      if (m != null) {
        final minutes = int.tryParse(m.group(1)!) ?? 0;
        if (minutes <= 10) return _ContactBucket.sharingNow;
      }
      return _ContactBucket.paused;
    }
    if (time.contains('h ago')) return _ContactBucket.paused;
    return _ContactBucket.offline;
  }

  bool _isLive(ContactDisplay c) =>
      _bucketFor(c) == _ContactBucket.sharingNow &&
      c.membershipStatus != 'invite';

  GridAvatarStatus _avatarStatusFor(ContactDisplay c) {
    switch (_bucketFor(c)) {
      case _ContactBucket.sharingNow:
        return GridAvatarStatus.live;
      case _ContactBucket.paused:
        return GridAvatarStatus.paused;
      case _ContactBucket.offline:
        return GridAvatarStatus.offline;
    }
  }

  String _placeLineFor(ContactDisplay c) {
    // We don't yet have a geocoded place; show the membership state or a
    // gentle fallback. Keeps the row visually balanced with the design.
    if (c.membershipStatus == 'invite') return 'Invite pending';
    final time = c.lastSeen;
    if (time == 'Offline' || time.isEmpty || time == '-') {
      return 'Last seen unknown';
    }
    return 'Sharing location';
  }

  String? _timeTextFor(ContactDisplay c) {
    final time = c.lastSeen;
    if (time.isEmpty) return null;
    if (time == 'Just now') return 'now';
    // Already short ("2m ago", "3h ago"); strip " ago" for compactness.
    if (time.endsWith(' ago')) return time.substring(0, time.length - 4);
    return time;
  }

  @override
  Widget build(BuildContext context) {
    // Single uniform surface for the whole subscreen — the Scaffold,
    // the outer container, and every list background all resolve to
    // GridTokens.surface so the sheet doesn't bleed to a darker tone
    // as the user scrolls past the bottom of the contact rows.
    return Material(
      color: GridTokens.surface,
      child: BlocListener<AvatarBloc, AvatarState>(
        listenWhen: (previous, current) =>
            previous.updateCounter != current.updateCounter,
        listener: (context, avatarState) {
          // Force rebuild when avatar updates occur
          setState(() {});
        },
        child: BlocConsumer<ContactsBloc, ContactsState>(
          listener: (context, state) {
            if (state is ContactsError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: ${state.message}'),
                  backgroundColor: GridTokens.danger,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
          },
          builder: (context, state) {
            if (state is ContactsLoading && !_hasShownInitialLoading) {
              _hasShownInitialLoading = true;
              return _buildLoadingState();
            }

            if (state is ContactsError) {
              return _buildErrorState(state.message);
            }

            if (state is ContactsLoaded) {
              return Consumer<UserLocationProvider>(
                builder: (context, locationProvider, child) {
                  final contactsWithLocation =
                      _getContactsWithCurrentLocation(
                    state.contacts,
                    locationProvider,
                  );

                  return contactsWithLocation.isEmpty
                      ? _buildEmptyState()
                      : Consumer<SyncManager>(
                          builder: (context, syncManager, child) {
                            final isSyncing =
                                syncManager.syncState != SyncState.ready;

                            // Handle sync state transitions
                            if (_previousSyncState != null &&
                                _previousSyncState != SyncState.ready &&
                                syncManager.syncState == SyncState.ready) {
                              _syncJustCompleted = true;
                              _showCheckmark = true;
                              _checkmarkAnimationController
                                  .forward()
                                  .then((_) {
                                if (mounted) {
                                  Future.delayed(
                                      const Duration(milliseconds: 200), () {
                                    if (mounted) {
                                      setState(() {
                                        _showCheckmark = false;
                                        _syncJustCompleted = false;
                                      });
                                      _checkmarkAnimationController.reset();
                                    }
                                  });
                                }
                              });
                            }
                            _previousSyncState = syncManager.syncState;

                            return _buildContactsList(
                              contactsWithLocation,
                              isSyncing: isSyncing,
                            );
                          },
                        );
                },
              );
            }

            return Center(
              child: Text(
                'No contacts',
                style: GoogleFonts.getFont(
                  'Geist',
                  color: GridTokens.text2,
                  fontSize: 14,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── List with sections (SHARING NOW / PAUSED / OFFLINE) ──
  Widget _buildContactsList(
    List<ContactDisplay> contacts, {
    required bool isSyncing,
  }) {
    // Group while preserving the upstream sort order (recent-first).
    final live = <ContactDisplay>[];
    final paused = <ContactDisplay>[];
    final offline = <ContactDisplay>[];
    for (final c in contacts) {
      switch (_bucketFor(c)) {
        case _ContactBucket.sharingNow:
          live.add(c);
          break;
        case _ContactBucket.paused:
          paused.add(c);
          break;
        case _ContactBucket.offline:
          offline.add(c);
          break;
      }
    }

    final items = <_ListItem>[];
    if (isSyncing || _showCheckmark) {
      items.add(const _ListItem.syncing());
    }
    if (live.isNotEmpty) {
      items.add(_ListItem.section('SHARING NOW', trailingCount: live.length));
      for (int i = 0; i < live.length; i++) {
        items.add(_ListItem.contact(live[i], isLast: i == live.length - 1));
      }
    }
    if (paused.isNotEmpty) {
      items.add(_ListItem.section('PAUSED', trailingCount: paused.length));
      for (int i = 0; i < paused.length; i++) {
        items.add(
            _ListItem.contact(paused[i], isLast: i == paused.length - 1));
      }
    }
    if (offline.isNotEmpty) {
      items.add(_ListItem.section('OFFLINE', trailingCount: offline.length));
      for (int i = 0; i < offline.length; i++) {
        items.add(
            _ListItem.contact(offline[i], isLast: i == offline.length - 1));
      }
    }

    return Container(
      color: GridTokens.surface,
      child: ListView.builder(
        controller: widget.scrollController,
        itemCount: items.length,
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        itemBuilder: (context, index) {
        final item = items[index];
          switch (item.kind) {
            case _ListItemKind.syncing:
              return _buildSyncingIndicator(isSyncing: isSyncing);
            case _ListItemKind.section:
              return GridSectionHeader(
                text: item.sectionTitle!,
                trailing:
                    item.trailingCount != null && item.trailingCount! > 0
                        ? GridMono(
                            '${item.trailingCount}',
                            color: GridTokens.text3,
                            size: 10.5,
                            letterSpacing: 0.12,
                          )
                        : null,
              );
            case _ListItemKind.contact:
              return _buildContactRow(item.contact!, isLast: item.isLast);
          }
        },
      ),
    );
  }

  Widget _buildContactRow(ContactDisplay contact, {required bool isLast}) {
    final isInvite = contact.membershipStatus == 'invite';
    final currentHomeserver = widget.roomService.getMyHomeserver();
    final showFullMatrixId = utils.isCustomHomeserver(currentHomeserver);
    final handle = showFullMatrixId
        ? contact.userId
        : '@${contact.userId.split(':')[0].replaceFirst('@', '')}';

    return GestureDetector(
      onLongPress: () => _showContactMenu(contact),
      child: GridContactRow(
        name: contact.displayName,
        handle: handle,
        userId: contact.userId,
        placeLine: _placeLineFor(contact),
        timeText: _timeTextFor(contact),
        live: _isLive(contact),
        avatarStatus: _avatarStatusFor(contact),
        showDivider: !isLast,
        statusKind: isInvite ? null : null,
        statusLabel: null,
        onTap: () {
          Provider.of<SelectedUserProvider>(context, listen: false)
              .setSelectedUserId(contact.userId, context);
        },
      ),
    );
  }

  Widget _buildSyncingIndicator({required bool isSyncing}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      height: 24,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _showCheckmark
              ? AnimatedBuilder(
                  animation: _checkmarkAnimationController,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _checkmarkFadeAnimation,
                      child: ScaleTransition(
                        scale: _checkmarkScaleAnimation,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: GridTokens.mint,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  },
                )
              : AnimatedBuilder(
                  animation: _dotsAnimation,
                  builder: (context, child) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: index <= _dotsAnimation.value
                                  ? GridTokens.mint
                                  : GridTokens.mint.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      color: GridTokens.surface,
      child: ListView.builder(
        controller: widget.scrollController,
        padding: const EdgeInsets.only(top: 8),
        itemCount: 6,
        itemBuilder: (context, index) {
          return _buildSkeletonContactRow();
        },
      ),
    );
  }

  Widget _buildSkeletonContactRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: GridTokens.hairline, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: GridTokens.surface2,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: 140,
                  decoration: BoxDecoration(
                    color: GridTokens.surface2,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 100,
                  decoration: BoxDecoration(
                    color: GridTokens.surface2.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 10,
            decoration: BoxDecoration(
              color: GridTokens.surface2.withOpacity(0.7),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      color: GridTokens.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: GridTokens.dangerSoft,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: GridTokens.danger,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: GridTokens.text,
                letterSpacing: -0.01,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                color: GridTokens.text2,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final myUserId = widget.roomService.getMyUserId();
    final handle = myUserId == null
        ? '@…'
        : '@${utils.localpart(myUserId)}';
    final qrData = myUserId ?? handle;

    return Container(
      color: GridTokens.surface,
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          // Handle / QR hero — gradient card with a tappable handle pill and
          // an inline QR tile. Designed to be the obvious first move when
          // there are no contacts yet.
          _HandleHeroCard(
            handle: handle,
            qrData: qrData,
            onCopy: () => _copyHandle(handle),
            onShare: () => _shareInviteLink(handle),
          ),
          const SizedBox(height: 18),
          GridButton(
            label: 'Share invite link',
            icon: Icons.ios_share_rounded,
            onPressed: () => _shareInviteLink(handle),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GridButton(
                  label: 'Scan code',
                  icon: Icons.qr_code_scanner_rounded,
                  style: GridButtonStyle.secondary,
                  onPressed: () => _showAddFriendModal(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GridButton(
                  label: 'Type handle',
                  icon: Icons.alternate_email_rounded,
                  style: GridButtonStyle.secondary,
                  onPressed: () => _showAddFriendModal(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Nothing is shared until both of you confirm.',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 12.5,
                color: GridTokens.text3,
                height: 1.45,
                letterSpacing: -0.005,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyHandle(String handle) async {
    await Clipboard.setData(ClipboardData(text: handle));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $handle'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<void> _shareInviteLink(String handle) async {
    try {
      await Share.share(
        'Join me on Grid! Download it at https://get.grid.lat and send $handle a friend request!',
        subject: 'Join me on Grid: Private Location Sharing!',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to share invite'),
          backgroundColor: GridTokens.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showExpandedAvatar(BuildContext context, String userId, String name) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: Hero(
                  tag: 'contact_menu_avatar_$userId',
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.width * 0.8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: GridTokens.surface,
                    ),
                    child: ClipOval(
                      child: UserAvatarBloc(
                        userId: userId,
                        size: MediaQuery.of(context).size.width * 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
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
            context.read<ContactsBloc>().add(LoadContacts());
          },
          onContactAdded: () {
            context.read<ContactsBloc>().add(RefreshContacts());
          },
        ),
      ),
    );
  }

  void _showContactMenu(ContactDisplay contact) {
    final currentHomeserver = widget.roomService.getMyHomeserver();
    final showFullMatrixId = utils.isCustomHomeserver(currentHomeserver);
    final handle = showFullMatrixId
        ? contact.userId
        : '@${contact.userId.split(':')[0].replaceFirst('@', '')}';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: GridTokens.surface,
            borderRadius: BorderRadius.circular(GridTokens.rLg),
            border: Border.all(color: GridTokens.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Identity header
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: GridTokens.surface2,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(GridTokens.rLg),
                    topRight: Radius.circular(GridTokens.rLg),
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _showExpandedAvatar(
                          context, contact.userId, contact.displayName),
                      child: Hero(
                        tag: 'contact_menu_avatar_${contact.userId}',
                        child: GridAvatar(
                          name: contact.displayName,
                          userId: contact.userId,
                          size: 48,
                          status: _avatarStatusFor(contact),
                          imageUrl: contact.avatarUrl,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contact.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: GridTokens.text,
                              letterSpacing: -0.01,
                            ),
                          ),
                          const SizedBox(height: 2),
                          GridMono(
                            handle,
                            color: GridTokens.text3,
                            size: 11,
                            letterSpacing: 0.02,
                            uppercase: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              _MenuRow(
                icon: Icons.person_rounded,
                iconBg: GridTokens.mintFaint,
                iconFg: GridTokens.mint,
                label: 'View profile',
                onTap: () {
                  Navigator.pop(context);
                  _showOptionsDialog(contact);
                },
              ),

              const Divider(
                  height: 1, thickness: 1, color: GridTokens.hairline),

              _MenuRow(
                icon: Icons.delete_outline_rounded,
                iconBg: GridTokens.dangerSoft,
                iconFg: GridTokens.danger,
                label: 'Remove contact',
                labelColor: GridTokens.danger,
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(contact);
                },
              ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(ContactDisplay contact) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            decoration: BoxDecoration(
              color: GridTokens.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: GridTokens.hairline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: GridTokens.dangerSoft,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(GridTokens.rXl),
                      topRight: Radius.circular(GridTokens.rXl),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: GridTokens.danger.withOpacity(0.18),
                          borderRadius:
                              BorderRadius.circular(GridTokens.rMd),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: GridTokens.danger,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Remove contact',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.015,
                                color: GridTokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "You can always add them back later.",
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: GridTokens.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Text(
                    'Remove "${contact.displayName}" from your contacts?',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: GridTokens.text2,
                      height: 1.45,
                    ),
                  ),
                ),

                // Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: GridButton(
                          label: 'Cancel',
                          style: GridButtonStyle.secondary,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GridButton(
                          label: 'Remove',
                          style: GridButtonStyle.danger,
                          onPressed: () {
                            Navigator.of(context).pop();
                            final contactName = contact.displayName;

                            context
                                .read<ContactsBloc>()
                                .add(DeleteContact(contact.userId));

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Removing $contactName from contacts...'),
                                backgroundColor: GridTokens.surface2,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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

// ── Internal helpers ────────────────────────────────────────────────

enum _ContactBucket { sharingNow, paused, offline }

enum _ListItemKind { syncing, section, contact }

class _ListItem {
  const _ListItem._({
    required this.kind,
    this.sectionTitle,
    this.trailingCount,
    this.contact,
    this.isLast = false,
  });

  const _ListItem.syncing()
      : kind = _ListItemKind.syncing,
        sectionTitle = null,
        trailingCount = null,
        contact = null,
        isLast = false;

  factory _ListItem.section(String title, {int? trailingCount}) => _ListItem._(
        kind: _ListItemKind.section,
        sectionTitle: title,
        trailingCount: trailingCount,
      );

  factory _ListItem.contact(ContactDisplay c, {required bool isLast}) =>
      _ListItem._(
        kind: _ListItemKind.contact,
        contact: c,
        isLast: isLast,
      );

  final _ListItemKind kind;
  final String? sectionTitle;
  final int? trailingCount;
  final ContactDisplay? contact;
  final bool isLast;
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.label,
    this.labelColor,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(GridTokens.rSm),
                ),
                child: Icon(icon, color: iconFg, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: labelColor ?? GridTokens.text,
                    letterSpacing: -0.01,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: GridTokens.text3, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty-state hero: gradient card with the user's @handle (tap to copy)
/// alongside an inline QR tile that the user can show to a friend.
class _HandleHeroCard extends StatelessWidget {
  const _HandleHeroCard({
    required this.handle,
    required this.qrData,
    required this.onCopy,
    required this.onShare,
  });

  final String handle;
  final String qrData;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GridTokens.mintFaint, GridTokens.surface],
        ),
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: GridTokens.mintSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 92,
                height: 92,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(GridTokens.rMd),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 76,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: GridTokens.mint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 9,
                        color: Color(0xFF04201A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GridMono(
                      'YOUR HANDLE',
                      size: 10,
                      letterSpacing: 0.12,
                      color: GridTokens.text3,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: GridTokens.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Send this to a friend so they can find you.',
                      maxLines: 2,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 12,
                        color: GridTokens.text2,
                        height: 1.35,
                        letterSpacing: -0.005,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CopyChip(handle: handle, onTap: onCopy),
        ],
      ),
    );
  }
}

class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.handle, required this.onTap});

  final String handle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Ink(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: GridTokens.surface,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.hairlineStrong),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.copy_rounded,
                size: 14,
                color: GridTokens.mint,
              ),
              const SizedBox(width: 8),
              Text(
                'Copy $handle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.005,
                  color: GridTokens.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
