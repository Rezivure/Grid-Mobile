import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/providers/room_provider.dart'; // Ensure you import your RoomProvider
import 'dart:math';


class GroupInvitationModal extends StatefulWidget {
  final String groupName;
  final String roomId;
  final String inviter;
  final int expiration;
  final Future<void> Function() refreshCallback; // Callback for refreshing after action

  GroupInvitationModal({
    required this.groupName,
    required this.roomId,
    required this.inviter,
    required this.expiration,
    required this.refreshCallback,
  });

  @override
  _GroupInvitationModalState createState() => _GroupInvitationModalState();
}

String calculateExpiryTime(int expiration) {
  DateTime now = DateTime.now();
  int timeNowSeconds = now.millisecondsSinceEpoch ~/ 1000;
  int timeDifferenceInSeconds = expiration - timeNowSeconds;

  if (timeDifferenceInSeconds <= 0) {
    return "Permanent";
  } else {
    int minutes = (timeDifferenceInSeconds / 60).round();
    int hours = (minutes / 60).round();
    int days = (hours / 24).round();

    if (days > 0) {
      return "$days days";
    } else if (hours > 0) {
      return "$hours hours";
    } else if (minutes > 0) {
      return "$minutes minutes";
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
    expiry = calculateExpiryTime(widget.expiration); // Move calculation here
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center, // Center content horizontally
        children: [
          RandomAvatar(widget.inviter.split(':')[0].replaceFirst('@', ''), height: 80, width: 80), // Centered avatar
          SizedBox(height: 16),
          Text(
            'Would you like to join the group "${widget.groupName}"?',
            textAlign: TextAlign.center, // Center the text
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 15),
          Text(
            'Invited by: @${widget.inviter.split(":").first.replaceFirst('@', '')}',
            textAlign: TextAlign.center, // Center the text
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
          Text(
            'Duration: $expiry',
            textAlign: TextAlign.center, // Center the text
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),

          if (_isProcessing) CircularProgressIndicator(),
        ],
      ),
      actions: [
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
            foregroundColor: colorScheme.surface,
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
    setState(() {
      _isProcessing = true;
    });

    try {
      // Accept the invitation using RoomProvider
      await Provider.of<RoomProvider>(context, listen: false).acceptInvitation(widget.roomId);
      Navigator.of(context).pop(); // Close the modal
      widget.refreshCallback(); // Trigger the callback to refresh
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Group invitation accepted.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to accept group invitation: $e")),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _declineGroupInvitation() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Decline the invitation using RoomProvider
      await Provider.of<RoomProvider>(context, listen: false).declineInvitation(widget.roomId);
      Navigator.of(context).pop(); // Close the modal
      widget.refreshCallback(); // Trigger the callback to refresh
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Group invitation declined.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to decline group invitation: $e")),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
}
