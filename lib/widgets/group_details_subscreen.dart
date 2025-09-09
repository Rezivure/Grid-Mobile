import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/widgets/status_indictator.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/models/room.dart' as GridRoom;
import 'user_avatar_bloc.dart';
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
import 'location_history_modal.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/widgets/group_avatar_bloc.dart';
import 'package:grid_frontend/widgets/group_markers_modal.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/services/database_service.dart';

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

  Future<bool> _canCurrentUserKick() async {
    try {
      final room = widget.roomService.client.getRoomById(widget.room.roomId);
      return room?.canKick ?? false;
    } catch (e) {
      print('Error checking kick permissions: $e');
      return false;
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
              content: const Text('User removed from group'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          
          // Refresh the member list immediately
          context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));
          
          // Handle the kick in the bloc
          await context.read<GroupsBloc>().handleMemberKicked(
              widget.room.roomId, userId);
              
          // Add a delayed refresh to ensure sync
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));
            }
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to remove user. You may not have permission.'),
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
            content: Text('Error removing user: $e'),
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

  void _showMemberMenu(GridUser user, String? memberStatus) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canKick = await _canCurrentUserKick();
    
    // Check if using custom homeserver
    final currentHomeserver = widget.roomService.getMyHomeserver();
    final showFullMatrixId = isCustomHomeserver(currentHomeserver);
    
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Member info header
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
                        userId: user.userId,
                        size: 40,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayName ?? localpart(user.userId),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            showFullMatrixId 
                                ? user.userId
                                : '@${user.userId.split(':')[0].replaceFirst('@', '')}',
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
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    // Remove from group option
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: canKick 
                              ? Colors.red.withOpacity(0.1)
                              : colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.person_remove_outlined,
                          color: canKick ? Colors.red : colorScheme.onSurface.withOpacity(0.3),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Remove from Group',
                        style: TextStyle(
                          color: canKick ? Colors.red : colorScheme.onSurface.withOpacity(0.3),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      enabled: canKick,
                      onTap: canKick ? () {
                        Navigator.pop(context);
                        _showKickConfirmation(user);
                      } : null,
                    ),
                    
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showKickConfirmation(GridUser user) {
    final colorScheme = Theme.of(context).colorScheme;
    
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
                Icons.person_remove_outlined,
                color: Colors.red,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Remove Member',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove "${user.displayName ?? localpart(user.userId)}" from this group?',
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
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _kickMember(user.userId);
              },
              child: const Text(
                'Remove',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
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
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
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
  
  void _showGroupMarkersModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GroupMarkersModal(
        roomId: widget.room.roomId,
        roomName: widget.room.name.split(':').length >= 5 
            ? widget.room.name.split(':')[3]
            : widget.room.name,
        mapIconRepository: MapIconRepository(DatabaseService()),
      ),
    );
  }
  
  void _showGroupDetailsMenu() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
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
              // Group info header
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
                      child: GroupAvatarBloc(
                        roomId: widget.room.roomId,
                        memberIds: widget.room.members,
                        size: 40,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.room.name.split(':').length >= 5 
                                ? widget.room.name.split(':')[3]
                                : widget.room.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            '${_filteredMembers.length} members',
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
                    Icons.info_outline,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Group Settings',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.8,
                      ),
                      child: GroupProfileModal(
                        room: widget.room,
                        roomService: widget.roomService,
                        sharingPreferencesRepo: widget.sharingPreferencesRepository,
                        onMemberAdded: () {
                          Navigator.pop(context);
                          _showAddGroupMemberModal();
                        },
                      ),
                    ),
                  );
                },
              ),
              
              // Add Member
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.person_add_outlined,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Add Member',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAddGroupMemberModal();
                },
              ),
              
              // Group History
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
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (BuildContext context) {
                      return LocationHistoryModal(
                        userId: widget.room.roomId,
                        userName: widget.room.name.split(':').length >= 5 
                            ? widget.room.name.split(':')[3]
                            : widget.room.name,
                        memberIds: _filteredMembers.map((m) => m.userId).toList(),
                      );
                    },
                  );
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
                    Icons.location_on,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  'View Markers',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showGroupMarkersModal();
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
                    Icons.exit_to_app_outlined,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Leave Group',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: _isLeaving 
                    ? null 
                    : () {
                        Navigator.pop(context);
                        _showLeaveConfirmationDialog();
                      },
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMemberTile(GridUser user, GroupsLoaded state, 
      List<UserLocation> userLocations) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Check if using custom homeserver
    final currentHomeserver = widget.roomService.getMyHomeserver();
    final showFullMatrixId = isCustomHomeserver(currentHomeserver);
    final userLocation = userLocations
        .cast<UserLocation?>()
        .firstWhere(
          (loc) => loc?.userId == user.userId,
          orElse: () => null,
        );

    final memberStatus = state.getMemberStatus(user.userId);
    final timeAgoText = userLocation != null
        ? TimeAgoFormatter.format(userLocation.timestamp)
        : 'Off Grid';

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
                .setSelectedUserId(user.userId, context);
          },
          onLongPress: () => _showMemberMenu(user, memberStatus),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                // Avatar with status indicator
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
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: colorScheme.primary.withOpacity(0.1),
                        child: UserAvatarBloc(
                          userId: user.userId,
                          size: 44,
                        ),
                      ),
                    ),
                    // Status dot
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: _buildStatusDot(timeAgoText, colorScheme, membershipStatus: memberStatus),
                    ),
                  ],
                ),
                
                const SizedBox(width: 12),
                
                // User information
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Display name
                      Text(
                        user.displayName ?? localpart(user.userId),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 2),
                      
                      // User ID subtitle
                      Text(
                        showFullMatrixId 
                            ? user.userId
                            : '@${user.userId.split(':')[0].replaceFirst('@', '')}',
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
                
                // Status indicator on the right
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusIndicator(
                      timeAgo: timeAgoText,
                      membershipStatus: memberStatus,
                    ),
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

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 80),
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
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildActionButtons() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _isProcessing ? null : () {
            _showGroupDetailsMenu();
          },
          icon: Icon(
            Icons.more_horiz,
            size: 20,
            color: colorScheme.onPrimary,
          ),
          label: Text(
            'Group Details',
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
                    ? SingleChildScrollView(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.all(16.0),
                        child: _buildEmptyState(),
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.all(16.0),
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