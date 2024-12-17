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

class GroupDetailsSubscreen extends StatefulWidget {
  final UserService userService;
  final RoomService roomService;
  final UserRepository userRepository;
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
    required this.userService,
  }) : super(key: key);

  @override
  _GroupDetailsSubscreenState createState() => _GroupDetailsSubscreenState();
}

class _GroupDetailsSubscreenState extends State<GroupDetailsSubscreen> {
  bool _isLeaving = false;
  bool _isProcessing = false;
  bool _isRefreshing = false;

  final TextEditingController _searchController = TextEditingController();
  List<GridUser> _filteredMembers = [];
  String? _currentUserId;
  Timer? _refreshTimer;


  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterMembers);
    _loadCurrentUser();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSubscreenSelected('group:${widget.room.roomId}');
      _refreshMembers();
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_isRefreshing) {
        _refreshMembers();
      }
    });

  }

  Future<void> _loadCurrentUser() async {
    _currentUserId = await widget.userService.getMyUserId();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(GroupDetailsSubscreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.roomId != widget.room.roomId) {
      _searchController.text = '';
      _onSubscreenSelected('group:${widget.room.roomId}');
      _refreshMembers();
    }
  }

  Future<void> _refreshMembers() async {
    if (_isRefreshing) return;

    _isRefreshing = true;
    try {
      context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));
      // Small delay before allowing next refresh
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      print('Error refreshing group members: $e');
    } finally {
      _isRefreshing = false;
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
          (user.displayName?.toLowerCase().contains(searchText) ?? false) ||
              user.userId.toLowerCase().contains(searchText))
              .toList();
        });
      }
    }
  }

  Widget _getSubtitleText(BuildContext context, GroupsLoaded state, GridUser user, UserLocation? userLocation) {
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
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Leave Group'),
          content: const Text('Are you sure you want to leave this group?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Leave'),
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
      await widget.roomService.leaveRoom(widget.room.roomId);
      if (mounted) {
        context.read<GroupsBloc>().add(RefreshGroups());
      }
      widget.onGroupLeft();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error leaving group: $e')),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return AddGroupMemberModal(
          roomId: widget.room.roomId,
          userService: widget.userService,
          roomService: widget.roomService,
          userRepository: widget.userRepository,
          onInviteSent: () {
            // Reload members when invite is sent
            context.read<GroupsBloc>().add(LoadGroupMembers(widget.room.roomId));
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userLocations = Provider.of<UserLocationProvider>(context).getAllUserLocations();

    return BlocBuilder<GroupsBloc, GroupsState>(
      builder: (context, state) {
        if (state is! GroupsLoaded || !state.hasMemberData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Always update filtered members when state changes
        if (state.selectedRoomMembers != null && _currentUserId != null) {
          final searchText = _searchController.text.toLowerCase();
          _filteredMembers = state.selectedRoomMembers!
              .where((user) => user.userId != _currentUserId)
              .where((user) =>
          (user.displayName?.toLowerCase().contains(searchText) ?? false) ||
              user.userId.toLowerCase().contains(searchText))
              .toList();
        }

        return Column(
          children: [
            CustomSearchBar(
              controller: _searchController,
              hintText: 'Search Members',
            ),
            Expanded(
              child: ListView.builder(
                controller: widget.scrollController,
                padding: EdgeInsets.zero,
                itemCount: _filteredMembers.length + 1,
                itemBuilder: (context, index) {
                  if (index < _filteredMembers.length) {
                    final user = _filteredMembers[index];
                    final userLocation = userLocations
                        .cast<UserLocation?>()
                        .firstWhere(
                          (loc) => loc?.userId == user.userId,
                      orElse: () => null,
                    );

                    return Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            radius: 30,
                            child: RandomAvatar(
                              user.userId.split(':')[0].replaceFirst('@', ''),
                              height: 60,
                              width: 60,
                            ),
                            backgroundColor: colorScheme.primary.withOpacity(0.2),
                          ),
                          title: Text(
                            user.displayName ?? user.userId,
                            style: TextStyle(color: colorScheme.onBackground),
                          ),
                          subtitle: _getSubtitleText(context, state, user, userLocation), // Use updated method
                          onTap: () {
                            Provider.of<SelectedUserProvider>(context, listen: false)
                                .setSelectedUserId(user.userId, context);
                          },
                        ),
                      ],
                    );
                  } else {
                    // Add Member and Leave Group buttons at the end of the list
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0)
                          .copyWith(top: 20.0),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 180,
                            child: ElevatedButton(
                              onPressed:
                              _isProcessing ? null : _showAddGroupMemberModal,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.onSurface,
                                foregroundColor: colorScheme.surface,
                                side: BorderSide(color: colorScheme.onSurface),
                                minimumSize: const Size(150, 40),
                              ),
                              child: const Text('Add Member'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 180,
                            child: ElevatedButton(
                              onPressed:
                              _isLeaving ? null : _showLeaveConfirmationDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                minimumSize: const Size(150, 40),
                              ),
                              child: _isLeaving
                                  ? const CircularProgressIndicator(color: Colors.red)
                                  : const Text('Leave Group'),
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
      },
    );
  }
}