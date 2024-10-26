// profile_modal.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter/services.dart';
import 'package:grid_frontend/providers/room_provider.dart';

class ProfileModal extends StatefulWidget {
  @override
  _ProfileModalState createState() => _ProfileModalState();
}

class _ProfileModalState extends State<ProfileModal> {
  bool _copied = false; // State variable to track if "Copied" should be shown

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final client = Provider.of<RoomProvider>(context, listen: false).client;
    final userId = client.userID ?? 'unknown';
    final userLocalpart = userId.split(':')[0].replaceFirst('@', '');

    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7, // 70% of screen height
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Row with avatar, username, and copy icon
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: colorScheme.primary.withOpacity(0.1),
                    child: RandomAvatar(userLocalpart),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Text(
                            userLocalpart,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onBackground,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.copy,
                            color: colorScheme.onBackground,
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: userLocalpart));
                            setState(() {
                              _copied = true;
                            });
                            Future.delayed(Duration(seconds: 2), () {
                              if (mounted) {
                                setState(() {
                                  _copied = false;
                                });
                              }
                            });
                          },
                        ),
                        if (_copied)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              'Copied',
                              style: TextStyle(
                                color: colorScheme.onBackground,
                                fontSize: 14,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),

              // Spacer to push QR code lower in the modal
              Spacer(flex: 1),

              // Centered QR code
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: userId,
                      version: QrVersions.auto,
                      size: 250.0,
                      backgroundColor: Colors.transparent,
                      foregroundColor: colorScheme.onBackground,
                    ),
                  ],
                ),
              ),

              Spacer(flex: 2), // More space below QR code

              // Close button at the bottom
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
