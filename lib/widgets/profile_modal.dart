import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter/services.dart';
import 'package:grid_frontend/services/user_service.dart';

import '../services/room_service.dart';

class ProfileModal extends StatefulWidget {
  final UserService userService;

  const ProfileModal({Key? key, required this.userService}) : super(key: key);

  @override
  _ProfileModalState createState() => _ProfileModalState();
}

class _ProfileModalState extends State<ProfileModal> {
  bool _copied = false;
  String? _userId;
  String? _relativeUserId;
  String? _userLocalpart;


  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<bool> isCustomServer() async {
    final roomService = Provider.of<RoomService>(context, listen: false);
    final homeserver = roomService.getMyHomeserver();
    return utils.isCustomHomeserver(homeserver);
  }

  Future<void> _loadUserId() async {
    final client = Provider.of<Client>(context, listen: false);
    var userId = client.userID;
    _userLocalpart = utils.localpart(userId!);

    bool isCustomServ = await isCustomServer();
    String relativeUserId;

    if (!isCustomServ) {
      // is grid server
      relativeUserId = '@${utils.localpart(userId)}';
    } else {
      relativeUserId = userId;
    }

    if (mounted) {
      setState(() {
        _userId = userId;
        _relativeUserId = relativeUserId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_userId == null) {
      return Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.background,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.background,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle indicator
            Container(
              margin: EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onBackground.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Header Section
                    Text(
                      'My Profile',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onBackground,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Share this QR code with friends to connect',
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onBackground.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 24),

                    // Profile Section
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.15),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withOpacity(0.05),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: colorScheme.primary.withOpacity(0.1),
                            child: RandomAvatar(
                              _userLocalpart!,
                              height: 60,
                              width: 60,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Username',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  _relativeUserId!,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              icon: Icon(
                                _copied ? Icons.check : Icons.copy,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _relativeUserId!));
                                setState(() {
                                  _copied = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Username copied to clipboard'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                Future.delayed(Duration(seconds: 2), () {
                                  if (mounted) {
                                    setState(() {
                                      _copied = false;
                                    });
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24),

                    // QR Code Section
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.15),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withOpacity(0.05),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                // Responsive QR code size based on available space
                                final maxSize = MediaQuery.of(context).size.width * 0.5;
                                final qrSize = maxSize.clamp(180.0, 220.0);
                                
                                return QrImageView(
                                  data: _relativeUserId!,
                                  version: QrVersions.auto,
                                  size: qrSize,
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                );
                              },
                            ),
                          ),
                          SizedBox(height: 16),
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.primary.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: colorScheme.primary,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Friends can scan this code to add you instantly',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 32),

                    // Close Button
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary,
                            colorScheme.primary.withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(0.4),
                            blurRadius: 12,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 22,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Close',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}