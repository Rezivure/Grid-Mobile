import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/components/modals/notice_continue_modal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';

class GroupInvitationModal extends StatefulWidget {
  final RoomService roomService;
  final String groupName;
  final String roomId;
  final String inviter;
  final int expiration;
  final Future<void> Function() refreshCallback;

  GroupInvitationModal({
    required this.groupName,
    required this.roomId,
    required this.inviter,
    required this.expiration,
    required this.refreshCallback,
    required this.roomService,
  });

  @override
  _GroupInvitationModalState createState() => _GroupInvitationModalState();
}

String calculateExpiryTime(int expiration) {
  DateTime now = DateTime.now();
  int timeNowSeconds = now.millisecondsSinceEpoch ~/ 1000;
  int timeDifferenceInSeconds = expiration - timeNowSeconds;

  if (expiration == -1 || timeDifferenceInSeconds <= 0) {
    return "Permanent";
  } else {
    int minutes = (timeDifferenceInSeconds / 60).round();
    int hours = (minutes / 60).round();
    int days = (hours / 24).round();

    if (days > 0) {
      return "$days day${days > 1 ? 's' : ''}";
    } else if (hours > 0) {
      return "$hours hour${hours > 1 ? 's' : ''}";
    } else if (minutes > 0) {
      return "$minutes minute${minutes > 1 ? 's' : ''}";
    } else {
      return "a few seconds";
    }
  }
}

class _GroupInvitationModalState extends State<GroupInvitationModal> {
  bool _isProcessing = false;
  late String expiry;

  @override
  void initState() {
    super.initState();
    expiry = calculateExpiryTime(widget.expiration);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle indicator
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header with close button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.group_add,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Group Invitation',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Group info section
                    _buildGroupInfoCard(theme, colorScheme),
                    
                    const SizedBox(height: 24),
                    
                    // Action buttons
                    if (_isProcessing)
                      _buildLoadingState(theme, colorScheme)
                    else
                      _buildActionButtons(theme, colorScheme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupInfoCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Group icon with inviter avatar
          Stack(
            alignment: Alignment.center,
            children: [
              // Background circle
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.group,
                  color: colorScheme.primary,
                  size: 40,
                ),
              ),
              // Inviter avatar in corner
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.surface,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: RandomAvatar(
                    widget.inviter.split(':')[0].replaceFirst('@', ''),
                    height: 32,
                    width: 32,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Group name
          Text(
            widget.groupName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          // Invitation message
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Invited by @${widget.inviter.split(":").first.replaceFirst('@', '')}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Duration: $expiry',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Join message
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You\'ll start sharing your location with group members once you join.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          CircularProgressIndicator(
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Processing invitation...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        // Join button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _acceptGroupInvitation,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.group_add, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Join Group',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Decline button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: _declineGroupInvitation,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.close, size: 20, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Decline',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _acceptGroupInvitation() async {
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final syncManager = Provider.of<SyncManager>(context, listen: false);
      final groupsBloc = context.read<GroupsBloc>();
      final mapBloc = context.read<MapBloc>();

      // Accept the invitation through SyncManager to ensure proper syncing
      await syncManager.acceptInviteAndSync(widget.roomId);

      // Close the modal immediately after successful join
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Group invitation accepted."),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Now do the cleanup and updates
      await Future.delayed(const Duration(milliseconds: 500));

      // Remove invite and update UI
      syncManager.removeInvite(widget.roomId);

      // Multiple updates to ensure UI synchronization
      groupsBloc.add(RefreshGroups());
      groupsBloc.add(LoadGroups());
      mapBloc.add(MapLoadUserLocations());

      // Staggered updates to ensure everything syncs properly
      Future.delayed(const Duration(milliseconds: 750), () {
        if (mounted) {
          groupsBloc.add(RefreshGroups());
          groupsBloc.add(LoadGroups());
          groupsBloc.add(LoadGroupMembers(widget.roomId));
        }
      });

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          groupsBloc.add(RefreshGroups());
          groupsBloc.add(LoadGroups());
          mapBloc.add(MapLoadUserLocations());
        }
      });

      // Call the refresh callback if it exists
      try {
        await widget.refreshCallback();
      } catch (callbackError) {
        print('Error in refresh callback: $callbackError');
        // Don't throw, as the join was successful
      }
    } catch (e) {
      print('Error in _acceptGroupInvitation: $e');
      print('Error type: ${e.runtimeType}');
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        
        // Only show the invalid invite modal for specific errors
        if (e.toString().contains('403') || e.toString().contains('not_in_room') || e.toString().contains('Invalid')) {
          Navigator.of(context).pop();
          Provider.of<SyncManager>(context, listen: false).removeInvite(widget.roomId);
          
          await showDialog(
            context: context,
            builder: (context) => NoticeContinueModal(
              message: "The invite is no longer valid. It may have been removed.",
              onContinue: () {},
            ),
          );
        } else {
          // For other errors, just show a snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error accepting invitation: ${e.toString()}"),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _declineGroupInvitation() async {
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Decline the invitation using RoomService
      await widget.roomService.declineInvitation(widget.roomId);

      // Remove the invitation from SyncManager
      Provider.of<SyncManager>(context, listen: false).removeInvite(widget.roomId);

      if (mounted) {
        Navigator.of(context).pop(); // Close the modal
        await widget.refreshCallback(); // Trigger the callback to refresh

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Group invitation declined."),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to decline group invitation: $e"),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
}