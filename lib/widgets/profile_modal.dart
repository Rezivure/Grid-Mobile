import 'package:flutter/material.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter/services.dart';
import 'package:grid_frontend/services/user_service.dart';

class ProfileModal extends StatefulWidget {
  final UserService userService;

  const ProfileModal({Key? key, required this.userService}) : super(key: key);

  @override
  _ProfileModalState createState() => _ProfileModalState();
}

class _ProfileModalState extends State<ProfileModal> {
  bool _copied = false;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final userId = await widget.userService.getMyUserId();
    if (mounted) {
      setState(() {
        _userId = userId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_userId == null) {
      return Material(
        color: colorScheme.background,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final userLocalpart = localpart(_userId!);

    return Material(
      color: colorScheme.background,
      child: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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

              Spacer(flex: 1),

              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: _userId!,
                      version: QrVersions.auto,
                      size: 250.0,
                      backgroundColor: colorScheme.background,
                      foregroundColor: colorScheme.onBackground,
                    ),
                  ],
                ),
              ),

              Spacer(flex: 2),

              Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.onSurface,
                    foregroundColor: colorScheme.surface,
                  ),
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