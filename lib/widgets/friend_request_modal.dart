import 'package:flutter/material.dart';
import 'package:grid_frontend/providers/room_provider.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart'; // Import the random_avatar package

class FriendRequestModal extends StatefulWidget {
  final String userId;
  final String displayName;
  final String roomId;
  final VoidCallback onResponse; // Callback for refreshing

  FriendRequestModal({
    required this.userId,
    required this.displayName,
    required this.roomId,
    required this.onResponse, // Add this parameter
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
            widget.userId.split(":").first.replaceFirst('@', ''), // Generate random avatar based on user ID
            height: 80.0,
            width: 80.0,
          ),
          SizedBox(height: 20),
          Text('${widget.userId.split(":").first.replaceFirst('@', '')}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text('Wants to connect with you. You will begin sharing locations once you accept.'),
          SizedBox(height: 20),
          if (_isProcessing) CircularProgressIndicator(),
          if (!_isProcessing)
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
    setState(() {
      _isProcessing = true;
    });

    try {
      await Provider.of<RoomProvider>(context, listen: false).acceptInvitation(widget.roomId);
      Navigator.of(context).pop(); // Close the modal
      widget.onResponse(); // Trigger the callback to refresh
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Friend request accepted.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error accepting the request: $e")),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _declineRequest() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await Provider.of<RoomProvider>(context, listen: false).declineInvitation(widget.roomId);
      Navigator.of(context).pop(); // Close the modal
      widget.onResponse(); // Trigger the callback to refresh
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Friend request declined.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error declining the request: $e")),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
}
