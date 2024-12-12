import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:grid_frontend/components/modals/notice_continue_modal.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';

class FriendRequestModal extends StatefulWidget {
  final RoomService roomService;
  final String userId;
  final String displayName;
  final String roomId;
  final Future<void> Function() onResponse; // Callback for refreshing

  FriendRequestModal({
    required this.userId,
    required this.displayName,
    required this.roomId,
    required this.onResponse,
    required this.roomService,
  });

  @override
  _FriendRequestModalState createState() => _FriendRequestModalState();
}

class _FriendRequestModalState extends State<FriendRequestModal> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RandomAvatar(
            widget.userId.split(":").first.replaceFirst('@', ''),
            height: 80.0,
            width: 80.0,
          ),
          SizedBox(height: 20),
          Text(
            widget.displayName,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          Text(
            'Wants to connect with you. You will begin sharing locations once you accept.',
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20),
          if (_isProcessing)
            CircularProgressIndicator()
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _declineRequest,
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
                  onPressed: _acceptRequest,
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
            ),
        ],
      ),
    );
  }

  Future<void> _acceptRequest() async {
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Accept invitation and sync via SyncManager
      await Provider.of<SyncManager>(context, listen: false).acceptInviteAndSync(widget.roomId);

      print("Refreshing contacts via bloc...");

      if (mounted) {
        // Dispatch RefreshContacts to update ContactsBloc
        context.read<ContactsBloc>().add(RefreshContacts());
      }

      if (mounted) {
        Navigator.of(context).pop(); // Close the modal
        await widget.onResponse(); // Execute callback to refresh any parent components

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Friend request accepted.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error accepting the request: $e")),
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

  Future<void> _declineRequest() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await widget.roomService.declineInvitation(widget.roomId);
      Provider.of<SyncManager>(context, listen: false).removeInvite(widget.roomId);
      Navigator.of(context).pop();
      await widget.onResponse();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Friend request declined.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error declining the request: $e")),
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