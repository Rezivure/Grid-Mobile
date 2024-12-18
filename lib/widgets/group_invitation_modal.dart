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

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RandomAvatar(
            widget.inviter.split(':')[0].replaceFirst('@', ''),
            height: 80,
            width: 80,
          ),
          SizedBox(height: 16),
          Text(
            'Would you like to join the group "${widget.groupName}"?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 15),
          Text(
            'Invited by: @${widget.inviter.split(":").first.replaceFirst('@', '')}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
          Text(
            'Duration: $expiry',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
          SizedBox(height: 20),
          if (_isProcessing)
            CircularProgressIndicator()
        ],
      ),
      actions: _isProcessing
          ? null
          : [
        ElevatedButton(
          onPressed: _declineGroupInvitation,
          child: Text('Decline', style: TextStyle(color: Colors.red)),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.surface,
            foregroundColor: Colors.red,
            side: BorderSide(color: Colors.red),
            minimumSize: Size(100, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _acceptGroupInvitation,
          child: Text('Accept'),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            minimumSize: Size(100, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
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

      // Wait briefly for room creation to complete
      await Future.delayed(const Duration(milliseconds: 500));

      // Remove invite and update UI
      syncManager.removeInvite(widget.roomId);

      // Multiple updates to ensure UI synchronization
      groupsBloc.add(RefreshGroups());
      groupsBloc.add(LoadGroups());
      mapBloc.add(MapLoadUserLocations());

      // Close the modal
      if (mounted) {
        Navigator.of(context).pop();
      }

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

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Group invitation accepted.")),
        );
      }

      // Call the refresh callback
      await widget.refreshCallback();
    } catch (e) {
      if (mounted) {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error accepting invitation: $e")),
        );

        // Close modal and show invalid invite notice if appropriate
        Navigator.of(context).pop();
        Provider.of<SyncManager>(context, listen: false).removeInvite(widget.roomId);

        await showDialog(
          context: context,
          builder: (context) => NoticeContinueModal(
            message: "The invite is no longer valid. It may have been removed.",
            onContinue: () {},
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
          SnackBar(content: Text("Group invitation declined.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to decline group invitation: $e")),
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