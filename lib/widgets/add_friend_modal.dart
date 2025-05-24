// add_friend_modal.dart

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:provider/provider.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/services/room_service.dart';

import '../blocs/groups/groups_bloc.dart';
import '../blocs/groups/groups_event.dart';
import '../services/sync_manager.dart';


class AddFriendModal extends StatefulWidget {
  final UserService userService;
  final RoomService roomService;
  final GroupsBloc groupsBloc;
  final VoidCallback? onGroupCreated;

  const AddFriendModal({required this.userService, Key? key, required this.roomService, required this.groupsBloc, required this.onGroupCreated}) : super(key: key);

  @override
  _AddFriendModalState createState() => _AddFriendModalState();
}


class _AddFriendModalState extends State<AddFriendModal> with SingleTickerProviderStateMixin {
  // Add Contact variables
  final TextEditingController _controller = TextEditingController();
  bool _isProcessing = false;

  // Create Group variables
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _memberInputController = TextEditingController();
  List<String> _members = [];
  double _sliderValue = 1;
  bool _isForever = false;
  String? _usernameError;
  String? _contactError;
  String? _matrixUserId = "";
  String? _friendQrCodeScan;

  // New variable for member limit error
  String? _memberLimitError;

  late TabController _tabController;

  // QR code scanning variables
  bool _isScanning = false;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _qrController;

  // Used to prevent multiple scans
  bool hasScanned = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

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

    // Add listener to clear _memberLimitError when the user types
    _memberInputController.addListener(() {
      if (_memberLimitError != null) {
        setState(() {
          _memberLimitError = null;
        });
      }
    });
  }

  bool isCustomHomeserver() {
    final homeserver = this.widget.roomService.getMyHomeserver().replaceFirst('https://', '');
    if (homeserver == dotenv.env['HOMESERVER']) {
      return false;
    }
    return true;
  }

  void _addContact() async {
    final inputText = _controller.text.trim();
    bool isCustomServer = isCustomHomeserver();

    String? rawInput = _friendQrCodeScan ?? _controller.text.trim();
    if (rawInput.isEmpty) {
      setState(() {
        _contactError = 'Please enter a username.';
      });
      return;
    }
    var normalizedUserId = rawInput.toLowerCase();
    if (!isCustomServer) {
      final homeserver = this.widget.roomService.getMyHomeserver().replaceFirst('https://', '');
      normalizedUserId = '@$normalizedUserId:$homeserver';
    }
    if (normalizedUserId.isNotEmpty) {
      if (mounted) {
        setState(() {
          _isProcessing = true;
          _contactError = null; // Reset error before trying to add
        });
      }
      try {
        bool userExists = await widget.userService.userExists(normalizedUserId!);
        if (!userExists) {
          if (mounted) {
            setState(() {
              _contactError = 'Invalid username: @$inputText';
              _isProcessing = false;
            });
          }
          return;
        }

        bool success = await this.widget.roomService.createRoomAndInviteContact(normalizedUserId);

        if (success) {
          // Clear _matrixUserId after successful use
          _matrixUserId = null;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Request sent.')),
            );
            Navigator.of(context).pop();
          }
        } else {
          if (mounted) {
            setState(() {
              _contactError = 'Already friends or request pending';
            });
          }
        }
      } catch (e) {
        // Catch any other errors
        if (mounted) {
          setState(() {
            _contactError = 'Error sending friend request';
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
            _friendQrCodeScan = scannedUserId;
            _addContact();
          });
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

  // Create Group methods
  void _addMember() async {
    if (_members.length >= 5) {
      setState(() {
        _memberLimitError = 'Limit reached. Create group first.';
      });
      return;
    }

    String inputUsername = _memberInputController.text.trim();
    if (inputUsername.isEmpty) {
      setState(() {
        _usernameError = 'Please enter a username.';
      });
      return;
    }


    String username = inputUsername.startsWith('@') ? inputUsername.substring(1) : inputUsername;

    if (_members.contains(username)) {
      setState(() {
        _usernameError = 'User already added.';
      });
      return;
    }

    var usernameLowercase = '${username.toLowerCase()}';
    var fullMatrixId = usernameLowercase;
    final homeserver = this.widget.roomService.getMyHomeserver().replaceFirst('https://', '');
    bool isCustomServer = isCustomHomeserver();
    if (isCustomServer) {
      fullMatrixId = '@$usernameLowercase';
    } else {
      fullMatrixId = '@$usernameLowercase:$homeserver';
    }

    final doesExist = await widget.userService.userExists(fullMatrixId);
    final isSelf = await widget.roomService.getMyUserId() == (fullMatrixId);

    if (!doesExist || isSelf) {
      setState(() {
        _usernameError = 'Invalid username: @$username';
      });
    } else {
      setState(() {
        _members.add(username);
        _usernameError = null; // Clear error on successful add
        _memberLimitError = null; // Clear limit error if member added successfully
        _memberInputController.clear();
      });
    }
  }

  void _removeMember(String username) {
    setState(() {
      _members.remove(username);
      // Clear the member limit error when a member is removed
      if (_memberLimitError != null && _members.length < 5) {
        _memberLimitError = null;
      }
    });
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty || _members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name and add members.')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final groupName = _groupNameController.text.trim();
      final durationInHours = _isForever ? 0 : _sliderValue.toInt();

      // Create the group and get the room ID
      final roomId = await widget.roomService.createGroup(groupName, _members, durationInHours);

      if (mounted) {
        // Wait briefly for room creation to complete
        await Future.delayed(const Duration(milliseconds: 500));

        final syncManager = Provider.of<SyncManager>(context, listen: false);
        await syncManager.handleNewGroupCreation(roomId);


        // Notify parent that group was created
        widget.onGroupCreated?.call();

        // Trigger multiple refreshes to ensure UI updates
        widget.groupsBloc.add(RefreshGroups());

        // Close the modal
        Navigator.pop(context);

        // After modal is closed, trigger more refreshes with delays
        Future.delayed(const Duration(milliseconds: 750), () {
          if (mounted) {
            widget.groupsBloc.add(RefreshGroups());
          }
        });

        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            widget.groupsBloc.add(RefreshGroups());
            widget.groupsBloc.add(LoadGroups());
          }
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating group. Does that user exist?')),
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

  // Helper Methods for New UI
  Widget _buildSectionCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.background,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onBackground.withOpacity(0.6),
            ),
          ),
          SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildQuickDurationButton(String label, int hours, ColorScheme colorScheme) {
    bool isSelected = _sliderValue == hours || (hours == 72 && _sliderValue >= 71);
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _sliderValue = hours.toDouble();
          _isForever = hours >= 71;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? colorScheme.primary 
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? colorScheme.primary 
                : colorScheme.outline.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: colorScheme.primary.withOpacity(0.3),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ] : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected 
                ? Colors.white 
                : colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildMemberCard(String username, ColorScheme colorScheme) {
    return Container(
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
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colorScheme.primary.withOpacity(0.1),
            child: RandomAvatar(
              username.toLowerCase(),
              height: 32,
              width: 32,
            ),
          ),
          SizedBox(width: 8),
          Text(
            '@${username.toLowerCase()}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          SizedBox(width: 8),
          GestureDetector(
            onTap: () => _removeMember(username),
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                color: Colors.red,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQRScannerView(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Section
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scan QR Code',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onBackground,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Point your camera at a friend\'s QR code to add them instantly',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onBackground.withOpacity(0.7),
              ),
            ),
          ],
        ),
        SizedBox(height: 32),

        // QR Scanner Section
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.background,
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
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: QRView(
                    key: qrKey,
                    onQRViewCreated: _onQRViewCreated,
                    overlay: QrScannerOverlayShape(
                      borderColor: colorScheme.primary,
                      borderRadius: 16,
                      borderLength: 30,
                      borderWidth: 4,
                      cutOutSize: 250,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Position the QR code within the frame',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onBackground.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 32),

        // Cancel Button
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.outline.withOpacity(0.3),
                colorScheme.outline.withOpacity(0.2),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ElevatedButton(
            onPressed: () {
              _qrController?.pauseCamera();
              setState(() {
                _isScanning = false;
              });
            },
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
                  Icons.arrow_back,
                  color: colorScheme.onSurface,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Back to Manual Entry',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddContactForm(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Section
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add New Contact',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onBackground,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Send a friend request to start sharing your location',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onBackground.withOpacity(0.7),
              ),
            ),
          ],
        ),
        SizedBox(height: 32),

        // Username Input Section
        _buildSectionCard(
          theme: theme,
          colorScheme: colorScheme,
          title: 'Username',
          subtitle: 'Enter your friend\'s username',
          child: Column(
            children: [
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: isCustomHomeserver() 
                      ? 'john:homeserver.io' 
                      : 'Enter username...',
                  prefixIcon: Icon(
                    Icons.person,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  prefixText: '@',
                  errorText: _contactError,
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: colorScheme.outline.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: colorScheme.outline.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.red,
                      width: 1,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.red,
                      width: 2,
                    ),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                ),
              ),
              if (_contactError == null) ...[
                SizedBox(height: 12),
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
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Secure location sharing will begin once accepted',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 24),

        // Action Buttons Section
        Column(
          children: [
            // Send Request Button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isProcessing
                      ? [
                          colorScheme.outline.withOpacity(0.3),
                          colorScheme.outline.withOpacity(0.2),
                        ]
                      : [
                          colorScheme.primary,
                          colorScheme.primary.withOpacity(0.8),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: _isProcessing
                    ? []
                    : [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.4),
                          blurRadius: 12,
                          offset: Offset(0, 6),
                        ),
                      ],
              ),
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _addContact,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: _isProcessing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Sending Request...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_add,
                            color: Colors.white,
                            size: 22,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Send Friend Request',
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
            SizedBox(height: 16),

            // OR Divider
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: colorScheme.outline.withOpacity(0.3),
                    thickness: 1,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: colorScheme.outline.withOpacity(0.3),
                    thickness: 1,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // QR Scanner Button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.05),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _scanQRCode,
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
                      Icons.qr_code_scanner,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Scan QR Code Instead',
                      style: TextStyle(
                        color: colorScheme.primary,
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
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabController.dispose();
    _qrController?.dispose();
    _groupNameController.dispose();
    _memberInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent, // Ensure modal background is transparent
      child: SingleChildScrollView(
        child: Container(
          color: Colors.transparent,
          padding: EdgeInsets.all(16.0),
          child: DefaultTabController(
            length: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tabs
                TabBar(
                  controller: _tabController,
                  labelColor: theme.textTheme.bodyMedium?.color,
                  unselectedLabelColor: theme.textTheme.bodySmall?.color,
                  indicatorColor: theme.textTheme.bodyMedium?.color,
                  tabs: [
                    Tab(text: 'Add Contact'),
                    Tab(text: 'Create Group'),
                  ],
                ),
                // Tab views
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Add Contact Tab - Redesigned
                      SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: _isScanning
                              ? _buildQRScannerView(theme, colorScheme)
                              : _buildAddContactForm(theme, colorScheme),
                        ),
                      ),
                      // Create Group Tab - Redesigned
                      SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header Section
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Create New Group',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onBackground,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Set up a group to share your location with multiple friends',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: colorScheme.onBackground.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 32),
                              
                              // Group Name Section
                              _buildSectionCard(
                                theme: theme,
                                colorScheme: colorScheme,
                                title: 'Group Name',
                                subtitle: 'Choose a memorable name',
                                child: TextField(
                                  controller: _groupNameController,
                                  maxLength: 14,
                                  decoration: InputDecoration(
                                    hintText: 'Enter group name...',
                                    filled: true,
                                    fillColor: colorScheme.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: colorScheme.outline.withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: colorScheme.outline.withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: colorScheme.primary,
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    counterText: '',
                                  ),
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              SizedBox(height: 24),

                              // Duration Section
                              _buildSectionCard(
                                theme: theme,
                                colorScheme: colorScheme,
                                title: 'Duration',
                                subtitle: 'How long should the group last?',
                                child: Column(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: colorScheme.primary.withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          SleekCircularSlider(
                                            min: 1,
                                            max: 72,
                                            initialValue: _sliderValue,
                                            appearance: CircularSliderAppearance(
                                              customWidths: CustomSliderWidths(
                                                trackWidth: 6,
                                                progressBarWidth: 12,
                                                handlerSize: 16,
                                              ),
                                              customColors: CustomSliderColors(
                                                trackColor: colorScheme.outline.withOpacity(0.2),
                                                progressBarColor: colorScheme.primary,
                                                dotColor: colorScheme.primary,
                                                hideShadow: false,
                                                shadowColor: colorScheme.primary.withOpacity(0.3),
                                                shadowMaxOpacity: 0.2,
                                              ),
                                              infoProperties: InfoProperties(
                                                modifier: (double value) {
                                                  if (value >= 71) {
                                                    _isForever = true;
                                                    return 'Forever';
                                                  } else {
                                                    _isForever = false;
                                                    return '${value.toInt()}h';
                                                  }
                                                },
                                                mainLabelStyle: TextStyle(
                                                  color: colorScheme.primary,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                bottomLabelStyle: TextStyle(
                                                  color: colorScheme.onBackground.withOpacity(0.6),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                bottomLabelText: _isForever ? 'Permanent group' : 'Hours until expiration',
                                              ),
                                              startAngle: 270,
                                              angleRange: 360,
                                              size: 180,
                                            ),
                                            onChange: (value) {
                                              setState(() {
                                                _sliderValue = value >= 71 ? 72 : value;
                                              });
                                            },
                                          ),
                                          SizedBox(height: 16),
                                          SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                _buildQuickDurationButton('1h', 1, colorScheme),
                                                SizedBox(width: 8),
                                                _buildQuickDurationButton('4h', 4, colorScheme),
                                                SizedBox(width: 8),
                                                _buildQuickDurationButton('12h', 12, colorScheme),
                                                SizedBox(width: 8),
                                                _buildQuickDurationButton('24h', 24, colorScheme),
                                                SizedBox(width: 8),
                                                _buildQuickDurationButton('∞', 72, colorScheme),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 24),

                              // Members Section
                              _buildSectionCard(
                                theme: theme,
                                colorScheme: colorScheme,
                                title: 'Add Members',
                                subtitle: 'Invite up to 5 friends to your group',
                                child: Column(
                                  children: [
                                    // Add Member Input
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _memberInputController,
                                            decoration: InputDecoration(
                                              hintText: isCustomHomeserver() ? 'john:homeserver.io' : 'Enter username...',
                                              prefixIcon: Icon(
                                                Icons.person_add,
                                                color: colorScheme.primary,
                                                size: 20,
                                              ),
                                              prefixText: '@',
                                              errorText: _usernameError ?? _memberLimitError,
                                              filled: true,
                                              fillColor: colorScheme.surface,
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide(
                                                  color: colorScheme.outline.withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide(
                                                  color: colorScheme.outline.withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide(
                                                  color: colorScheme.primary,
                                                  width: 2,
                                                ),
                                              ),
                                              errorBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide(
                                                  color: Colors.red,
                                                  width: 1,
                                                ),
                                              ),
                                              focusedErrorBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide(
                                                  color: Colors.red,
                                                  width: 2,
                                                ),
                                              ),
                                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                            ),
                                            style: TextStyle(
                                              color: colorScheme.onSurface,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                colorScheme.primary,
                                                colorScheme.primary.withOpacity(0.8),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: colorScheme.primary.withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: ElevatedButton(
                                            onPressed: _addMember,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.transparent,
                                              shadowColor: Colors.transparent,
                                              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                            ),
                                            child: Text(
                                              'Add',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 20),
                                    
                                    // Members List
                                    if (_members.isNotEmpty) ...[
                                      Container(
                                        padding: EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surface,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: colorScheme.outline.withOpacity(0.2),
                                            width: 1,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.people,
                                                  color: colorScheme.primary,
                                                  size: 20,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Group Members (${_members.length}/5)',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: colorScheme.onSurface,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 16),
                                            Wrap(
                                              spacing: 16,
                                              runSpacing: 16,
                                              children: _members.map((username) => _buildMemberCard(username, colorScheme)).toList(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else ...[
                                      Container(
                                        padding: EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surface.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: colorScheme.outline.withOpacity(0.2),
                                            width: 1,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(
                                              Icons.people_outline,
                                              color: colorScheme.onSurface.withOpacity(0.4),
                                              size: 48,
                                            ),
                                            SizedBox(height: 12),
                                            Text(
                                              'No members added yet',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: colorScheme.onSurface.withOpacity(0.6),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Add friends to get started',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: colorScheme.onSurface.withOpacity(0.4),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              SizedBox(height: 32),

                              // Create Button
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: (_isProcessing ||
                                        _members.isEmpty ||
                                        _groupNameController.text.trim().isEmpty)
                                        ? [
                                            colorScheme.outline.withOpacity(0.3),
                                            colorScheme.outline.withOpacity(0.2),
                                          ]
                                        : [
                                            colorScheme.primary,
                                            colorScheme.primary.withOpacity(0.8),
                                          ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: (_isProcessing ||
                                      _members.isEmpty ||
                                      _groupNameController.text.trim().isEmpty)
                                      ? []
                                      : [
                                          BoxShadow(
                                            color: colorScheme.primary.withOpacity(0.4),
                                            blurRadius: 12,
                                            offset: Offset(0, 6),
                                          ),
                                        ],
                                ),
                                child: ElevatedButton(
                                  onPressed: (_isProcessing ||
                                      _members.isEmpty ||
                                      _groupNameController.text.trim().isEmpty)
                                      ? null
                                      : _createGroup,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: EdgeInsets.symmetric(vertical: 18),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  child: _isProcessing
                                      ? Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Text(
                                              'Creating Group...',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.group_add,
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Create Group',
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
                // Close button at the bottom
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

      ),
    );
  }
}
