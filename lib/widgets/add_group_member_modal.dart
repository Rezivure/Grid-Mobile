import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import '../../providers/room_provider.dart';

class AddGroupMemberModal extends StatefulWidget {
  final String roomId; // Room ID where the user will be invited

  AddGroupMemberModal({required this.roomId});

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
    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    final inputText = _controller.text.trim();
    String username;

    if (_matrixUserId != null && _matrixUserId!.isNotEmpty) {
      username = _matrixUserId!;
    } else {
      username = inputText;
    }

    String normalizedUserId = username.startsWith('@')
        ? username
        : '@$username:${dotenv.env['HOMESERVER']}';

    if (username.isNotEmpty) {
      if (mounted) {
        setState(() {
          _isProcessing = true;
          _contactError = null; // Reset error before trying to add
        });
      }
      try {
        // Check if the user exists before sending an invite.
        bool userExists = await roomProvider.userExists(normalizedUserId);
        if (!userExists) {
          if (mounted) {
            setState(() {
              _contactError = 'The user $username does not exist.';
              _isProcessing = false;
            });
          }
          return;
        }

        // Check if the user is already in the group.
        bool isAlreadyInGroup = await roomProvider.isUserInRoom(widget.roomId, normalizedUserId);
        if (isAlreadyInGroup) {
          if (mounted) {
            setState(() {
              _contactError = 'The user $username is already in the group.';
              _isProcessing = false;
            });
          }
          return;
        }

        // Proceed with inviting the user to the group.
        await roomProvider.client.inviteUser(widget.roomId, normalizedUserId);

        // Show success message and pop the modal if mounted
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invite sent successfully to $username.')),
          );
        }

        // Clear _matrixUserId after use
        _matrixUserId = null;
      } catch (e) {
        if (mounted) {
          setState(() {
            _contactError = 'Failed to send invite: $e';
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
    } else {
      if (mounted) {
        setState(() {
          _contactError = 'Please enter a valid username';
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
        print('Scanned QR Code: $scannedUserId');

        if (scannedUserId.isNotEmpty) {
          hasScanned = true;
          controller.pauseCamera(); // Pause the camera to avoid rescanning
          setState(() {
            _isScanning = false;
            _matrixUserId = scannedUserId;
            _controller.text = scannedUserId.split(":").first.replaceFirst('@', '');
          });
          _addMember();
        } else {
          print('QR Code data is empty');
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
    return SafeArea(
      child: GestureDetector(
        onTap: () {
          // Close the keyboard when tapping outside
          FocusScope.of(context).unfocus();
        },
        child: SingleChildScrollView(
          // This ensures the modal adjusts when the keyboard appears
          child: Padding(
            // Adjust padding when keyboard is visible
            padding: EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 16.0,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
            ),
            child: Center(
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
                        borderColor:
                        theme.textTheme.bodyMedium?.color ?? Colors.black,
                        borderRadius: 10,
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
                    child: Text('Cancel'),
                  ),
                ],
              )
                  : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Styled Text Field for Add Group Member
                  Container(
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                      style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color),
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _addMember,
                    child: _isProcessing
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Send Invite'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          horizontal: 40, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  // Scan QR Code Icon
                  Container(
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(Icons.qr_code_scanner),
                      onPressed: _scanQRCode,
                      iconSize: 50,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
