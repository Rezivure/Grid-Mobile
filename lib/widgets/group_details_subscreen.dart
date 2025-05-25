import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:grid_frontend/widgets/status_indictator.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/models/room.dart' as GridRoom;
import 'package:grid_frontend/models/grid_user.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import '../blocs/groups/groups_event.dart';
import '../blocs/groups/groups_state.dart';
import '../services/user_service.dart';
import '../utilities/time_ago_formatter.dart';
import 'add_group_member_modal.dart';
import 'group_profile_modal.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';

class GroupDetailsSubscreen extends StatefulWidget {
  final UserService userService;
  final RoomService roomService;
  final UserRepository userRepository;
  final SharingPreferencesRepository sharingPreferencesRepository;
  final ScrollController scrollController;
  final GridRoom.Room room;
  final VoidCallback onGroupLeft;

  const GroupDetailsSubscreen({
    Key? key,
    required this.scrollController,
    required this.room,
    required this.onGroupLeft,
    required this.roomService,
    required this.userRepository,
    required this.sharingPreferencesRepository,
    required this.userService,
  }) : super(key: key);

  @override
  _GroupDetailsSubscreenState createState() => _GroupDetailsSubscreenState();
}

class _GroupDetailsSubscreenState extends State<GroupDetailsSubscreen>
    with TickerProviderStateMixin {
  bool _isLeaving = false;
  bool _isProcessing = false;
  bool _isRefreshing = false;
  bool _isInitialLoad = true;

  final TextEditingController _searchController = TextEditingController();
  List<GridUser> _filteredMembers = [];
  String? _currentUserId;
  Timer? _refreshTimer;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    
    _searchController.addListener(_filterMembers);
    _loadCurrentUser();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSubscreenSelected('group:${widget.room.roomId}');
      context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));
      _fadeController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _searchController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    _currentUserId = await widget.userService.getMyUserId();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshMembers();
  }

  Future<void> _refreshMembers() async {
    if (!mounted) return;
    context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));
  }

  @override
  void didUpdateWidget(GroupDetailsSubscreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.roomId != widget.room.roomId) {
      _onSubscreenSelected('group:${widget.room.roomId}');
      _refreshMembers();
    }
  }

  Future<void> _kickMember(String userId) async {
    try {
      final success = await widget.roomService.kickMemberFromRoom(
          widget.room.roomId, userId);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('User kicked from group'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          await context.read<GroupsBloc>().handleMemberKicked(
              widget.room.roomId, userId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to kick. Only group creator can kick.'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error kicking user: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _onSubscreenSelected(String subscreen) {
    Provider.of<SelectedSubscreenProvider>(context, listen: false)
        .setSelectedSubscreen(subscreen);
  }

  void _filterMembers() {
    if (mounted) {
      final state = context.read<GroupsBloc>().state;
      if (state is GroupsLoaded && state.selectedRoomMembers != null) {
        final searchText = _searchController.text.toLowerCase();
        setState(() {
          _filteredMembers = state.selectedRoomMembers!
              .where((user) => user.userId != _currentUserId)
              .where((user) =>
                  (user.displayName?.toLowerCase().contains(searchText) ??
                      false) ||
                  user.userId.toLowerCase().contains(searchText))
              .toList();
        });
      }
    }
  }

  Widget _getSubtitleText(BuildContext context, GroupsLoaded state,
      GridUser user, UserLocation? userLocation) {
    final memberStatus = state.getMemberStatus(user.userId);
    final timeAgoText = userLocation != null
        ? TimeAgoFormatter.format(userLocation.timestamp)
        : 'Off Grid';

    return StatusIndicator(
      timeAgo: timeAgoText,
      membershipStatus: memberStatus,
    );
  }

  Future<void> _showLeaveConfirmationDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.exit_to_app,
                color: colorScheme.error,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Leave Group',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to leave this group? This action cannot be undone.',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurface.withOpacity(0.7),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Leave'),
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
      await widget.roomService.leaveRoom(widget.room.roomId);
      if (mounted) {
        context.read<GroupsBloc>().add(RefreshGroups());
      }
      widget.onGroupLeft();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error leaving group: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLeaving = false;
        });
      }
    }
  }

  void _showAddGroupMemberModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: AddGroupMemberModal(
          roomId: widget.room.roomId,
          userService: widget.userService,
          roomService: widget.roomService,
          userRepository: widget.userRepository,
          onInviteSent: () {
            context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));
          },
        ),
      ),
    );
  }

  Widget _buildMemberTile(GridUser user, GroupsLoaded state, 
      List<UserLocation> userLocations) {
    final colorScheme = Theme.of(context).colorScheme;
    final userLocation = userLocations
        .cast<UserLocation?>()
        .firstWhere(
          (loc) => loc?.userId == user.userId,
          orElse: () => null,
        );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Slidable(
        key: ValueKey(user.userId),
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (_) => _kickMember(user.userId),
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              icon: Icons.person_remove_outlined,
              label: 'Kick',
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.primary.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 26,
              backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
              child: RandomAvatar(
                user.userId.split(':')[0].replaceFirst('@', ''),
                height: 48,
                width: 48,
              ),
            ),
          ),
          title: Text(
            user.displayName ?? localpart(user.userId),
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _getSubtitleText(context, state, user, userLocation),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: colorScheme.onSurface.withOpacity(0.4),
            size: 20,
          ),
          onTap: () {
            Provider.of<SelectedUserProvider>(context, listen: false)
                .setSelectedUserId(user.userId, context);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.group_outlined,
                size: 48,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "It's lonely here!",
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Invite friends to join this group',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Group Settings Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => GroupProfileModal(
                    room: widget.room,
                    roomService: widget.roomService,
                    sharingPreferencesRepo: widget.sharingPreferencesRepository,
                    onMemberAdded: () {
                      Navigator.pop(context);
                      _showAddGroupMemberModal();
                    },
                  ),
                );
              },
              icon: Icon(
                Icons.settings_outlined,
                size: 20,
                color: colorScheme.onPrimary,
              ),
              label: Text(
                'Group Settings',
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Leave Group Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _isLeaving ? null : _showLeaveConfirmationDialog,
              icon: _isLeaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: colorScheme.error,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      Icons.exit_to_app_outlined,
                      size: 20,
                      color: colorScheme.error,
                    ),
              label: Text(
                _isLeaving ? 'Leaving...' : 'Leave Group',
                style: TextStyle(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userLocations = Provider.of<UserLocationProvider>(context)
        .getAllUserLocations();

    return BlocBuilder<GroupsBloc, GroupsState>(
      buildWhen: (previous, current) {
        if (previous is GroupsLoaded && current is GroupsLoaded) {
          return previous.selectedRoomId != current.selectedRoomId ||
              previous.selectedRoomMembers != current.selectedRoomMembers ||
              previous.membershipStatuses != current.membershipStatuses;
        }
        return true;
      },
      builder: (context, state) {
        if (state is! GroupsLoaded) {
          return Column(
            children: [
              CustomSearchBar(
                controller: _searchController,
                hintText: 'Search Members',
              ),
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          );
        }

        if (state.selectedRoomMembers != null && _currentUserId != null) {
          final searchText = _searchController.text.toLowerCase();
          _filteredMembers = state.selectedRoomMembers!
              .where((user) => user.userId != _currentUserId)
              .where((user) =>
                  (user.displayName?.toLowerCase().contains(searchText) ??
                      false) ||
                  user.userId.toLowerCase().contains(searchText))
              .toList();
        }

        return FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              CustomSearchBar(
                controller: _searchController,
                hintText: 'Search Members',
              ),
              
              Expanded(
                child: _filteredMembers.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        itemCount: _filteredMembers.length + 1,
                        itemBuilder: (context, index) {
                          if (index < _filteredMembers.length) {
                            final user = _filteredMembers[index];
                            return _buildMemberTile(
                              user,
                              state,
                              userLocations,
                            );
                          } else {
                            return _buildActionButtons();
                          }
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}