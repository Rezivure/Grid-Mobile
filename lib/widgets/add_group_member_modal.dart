import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:matrix/matrix_api_lite/generated/model.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';


import '../repositories/user_repository.dart';


class AddGroupMemberModal extends StatefulWidget {
  final String roomId;
  final UserService userService;
  final RoomService roomService;
  final UserRepository userRepository;
  final VoidCallback? onInviteSent;

  AddGroupMemberModal({required this.roomId, required this.userService, required this.roomService, required this.userRepository, required this.onInviteSent});

  @override
  _AddGroupMemberModalState createState() => _AddGroupMemberModalState();
}

class _AddGroupMemberModalState extends State<AddGroupMemberModal> {
  final TextEditingController _controller = TextEditingController();
  bool _isProcessing = false;

  // QR code scanning variables
  bool _isScanning = false;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _qrController;
  bool hasScanned = false;
  String? _matrixUserId = "";
  String? _contactError;

  @override
  void initState() {
    super.initState();

    _controller.addListener(() {
      if (_contactError != null) {
        setState(() {
          _contactError = null;
        });
      }
      // Reset _matrixUserId if the user types in the text field
      if (_controller.text.isNotEmpty) {
        _matrixUserId = null;
      }
    });
  }

  void _addMember() async {
    const int MAX_GROUP_MEMBERS = 15;

    final inputText = _controller.text.trim();
    String username;
    if (_matrixUserId != null && _matrixUserId!.isNotEmpty) {
      username = _matrixUserId!;
    } else {
      username = inputText;
    }


    var usernameLowercase = username.toLowerCase();
    final homeserver = widget.roomService.getMyHomeserver().replaceFirst('https://', '');
    final fullMatrixId = '@$usernameLowercase:$homeserver';

    if (username.isEmpty) {
      if (mounted) {
        setState(() {
          _contactError = 'Please enter a valid username';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isProcessing = true;
        _contactError = null;
      });
    }

    try {


      // check if inviting self
      final usernameLowercase = username.toLowerCase();
      final isSelf = (widget.roomService.getMyUserId() == fullMatrixId);
      if (isSelf) {
        if (mounted) {
          setState(() {
            _contactError = 'You cannot invite yourself to the group.';
            _isProcessing = false;
          });
        }
        return;
      }

      // Get and validate room
      final room = widget.roomService.client.getRoomById(widget.roomId);
      if (room == null) {
        throw Exception('Room not found');
      }

      // Check invite permissions
      if (!room.canInvite) {
        if (mounted) {
          setState(() {
            _contactError = 'You do not have permission to invite members to this group.';
            _isProcessing = false;
          });
        }
        return;
      }

      // Check member limit
      final memberCount = room
          .getParticipants()
          .where((member) =>
      member.membership == Membership.join ||
          member.membership == Membership.invite)
          .length;

      if (memberCount >= MAX_GROUP_MEMBERS) {
        if (mounted) {
          setState(() {
            _contactError = 'Group has reached maximum capacity: $MAX_GROUP_MEMBERS';
            _isProcessing = false;
          });
        }
        return;
      }

      // Verify user exists
      if (!await widget.userService.userExists(fullMatrixId)) {
        if (mounted) {
          setState(() {
            _contactError = 'The user $username does not exist.';
            _isProcessing = false;
          });
        }
        return;
      }

      // Check if already in group
      if (await widget.roomService.isUserInRoom(widget.roomId, fullMatrixId)) {
        if (mounted) {
          setState(() {
            _contactError = 'The user $username is already in the group.';
            _isProcessing = false;
          });
        }
        return;
      }

      // Send the matrix invite
      await widget.roomService.client.inviteUser(widget.roomId, fullMatrixId);

      // Let GroupsBloc handle the state updates
      context.read<GroupsBloc>().handleNewMemberInvited(widget.roomId, fullMatrixId);

      if (widget.onInviteSent != null) {
        widget.onInviteSent!();
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invite sent successfully to ${localpart(fullMatrixId)}.')),
        );
      }

      _matrixUserId = null;

    } catch (e) {
      log('Error adding member', error: e);
      if (mounted) {
        setState(() {
          _contactError = 'Failed to send invite. Do you have permissions?';
          _isProcessing = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // QR code scanning methods
  void _scanQRCode() {
    setState(() {
      _isScanning = true;
    });
  }

  void _onQRViewCreated(QRViewController controller) {
    _qrController = controller;
    controller.scannedDataStream.listen((scanData) async {
      if (!hasScanned) {
        String scannedUserId = scanData.code ?? '';
        log('Scanned QR Code: $scannedUserId');

        if (scannedUserId.isNotEmpty) {
          hasScanned = true;
          controller.pauseCamera(); // Pause the camera to avoid rescanning
          setState(() {
            _isScanning = false;
            _matrixUserId = scannedUserId;
            _controller.text = scannedUserId
                .split(":")
                .first
                .replaceFirst('@', '');
          });
          _addMember();
        } else {
          log('QR Code data is empty');
        }
      }
    });
  }

  void _resetScan() {
    hasScanned = false;
    _qrController?.resumeCamera();
  }

  @override
  void dispose() {
    _controller.dispose();
    _qrController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        // Dismiss keyboard on tap outside
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery
                .of(context)
                .viewInsets
                .bottom, // Adjust for keyboard
          ),
          child: Container(
            color: Colors.transparent,
            padding: EdgeInsets.all(16.0),
            child: _isScanning
                ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Scan QR Code',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
                SizedBox(height: 10),
                Container(
                  height: 300,
                  child: QRView(
                    key: qrKey,
                    onQRViewCreated: _onQRViewCreated,
                    overlay: QrScannerOverlayShape(
                      borderColor: theme.textTheme.bodyMedium?.color ??
                          Colors.black,
                      borderRadius: 36,
                      borderLength: 30,
                      borderWidth: 10,
                      cutOutSize: 250,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    _qrController?.pauseCamera();
                    setState(() {
                      _isScanning = false;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.onSurface,
                    foregroundColor: colorScheme.surface,
                  ),
                  child: Text('Cancel'),
                ),
              ],
            )
                : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 300, // Set a fixed width for the text field
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.light
                          ? theme.cardColor
                          : theme.colorScheme.surface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(36),
                      border: Theme.of(context).brightness == Brightness.dark
                          ? Border.all(color: theme.colorScheme.surface.withOpacity(0.15), width: 1)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Enter username',
                        prefixText: '@',
                        errorText: _contactError,
                        filled: true,
                        fillColor: theme.colorScheme.onBackground.withOpacity(0.15),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                    ),
                  ),
                ),
                SizedBox(height: 8), // Space between the TextField and subtext
                Text(
                  'Secure location sharing begins once accepted.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isProcessing ? null : _addMember,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(35),
                    ),
                    backgroundColor: colorScheme.onSurface,
                    foregroundColor: colorScheme.surface,
                  ),
                  child: _isProcessing
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text('Send Request'),
                ),
                SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.light ? theme.cardColor : null,
                    borderRadius: BorderRadius.circular(35),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _scanQRCode,
                    icon: Icon(
                      Icons.qr_code_scanner,
                      color: Theme.of(context).brightness == Brightness.light
                          ? colorScheme.primary
                          : colorScheme.surface,
                    ),
                    label: Text(
                      'Scan QR Code',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.light
                            ? colorScheme.onSurface
                            : colorScheme.surface,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(35),
                      ),
                      backgroundColor: Theme.of(context).brightness == Brightness.light
                          ? colorScheme.surface
                          : colorScheme.primary,
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
