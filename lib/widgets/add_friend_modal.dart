// add_friend_modal.dart

import 'package:flutter/material.dart';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
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

  void _addContact() async {
    final inputText = _controller.text.trim();
    String username;
    if (_matrixUserId != null && _matrixUserId!.isNotEmpty) {
      username = _matrixUserId!;
    } else {
      username = inputText;
    }
    var normalized = normalizeUser(username);
    String? normalizedUserId = normalized['matrixUserId'];

    if (username.isNotEmpty) {
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

        // User exists, proceed with invitation

        await this.widget.roomService.createRoomAndInviteContact(normalizedUserId);
        // Clear _matrixUserId after use
        _matrixUserId = null;
        // Only pop the modal if the widget is still mounted
        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        // Catch any other errors
        if (mounted) {
          setState(() {
            _contactError = 'Error adding user: ${e.toString()}';
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
          });
          _addContact();
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

    final usernameLowercase = username.toLowerCase();
    final doesExist = await this.widget.userService.userExists('@$usernameLowercase:${dotenv.env['HOMESERVER']}');

    if (!doesExist) {
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
          SnackBar(content: Text('Error creating group: $e')),
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
                      // Add Contact Tab
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _isScanning
                            ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Scan a Profile QR',
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
                                  borderColor: theme.textTheme.bodyMedium?.color ?? Colors.black,
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
                              child: Text('Cancel'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.onSurface,
                                foregroundColor: colorScheme.surface,
                              )
                            ),
                          ],
                        )
                            : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Styled Text Field for Add Contact
                              Container(
                                decoration: BoxDecoration(
                                  color: theme.cardColor,
                                  borderRadius: BorderRadius.circular(36),
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
                                      borderRadius: BorderRadius.circular(1),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  ),
                                  style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                                ),
                              ),
                              SizedBox(height: 8), // Space between the TextField and subtext
                              Text(
                                'Secure location sharing will begin once accepted.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: _isProcessing ? null : _addContact,
                                child: _isProcessing
                                    ? CircularProgressIndicator(color: Colors.white)
                                    : Text('Send Request'),
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(35),
                                  ),
                                  backgroundColor: colorScheme.onSurface,
                                  foregroundColor: colorScheme.surface,
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
                                child: // "Scan QR Code" Button with Text and Icon
                                ElevatedButton.icon(
                                  onPressed: _scanQRCode,
                                  icon: Icon(
                                    Icons.qr_code_scanner,
                                    color: colorScheme.primary,
                                  ),
                                  label: Text(
                                    'Scan QR Code',
                                    style: TextStyle(color: colorScheme.onSurface),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(35),
                                    ),
                                    iconColor: colorScheme.primary, // Set the button color if needed
                                    backgroundColor: colorScheme.surface,
                                  ),
                                ),

                              ),
                            ],
                          ),
                        ),
                      ),
                      // Create Group Tab
                      SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              // Styled Group Name Input
                              Container(
                                decoration: BoxDecoration(
                                  color: theme.cardColor,
                                  borderRadius: BorderRadius.circular(36),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: TextField(
                                  controller: _groupNameController,
                                  decoration: InputDecoration(
                                    hintText: 'Enter group name',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(1),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  ),
                                  style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                                ),
                              ),
                              SizedBox(height: 20),
                              // Circular Slider
                              SleekCircularSlider(
                                min: 1,
                                max: 72,
                                initialValue: _sliderValue,
                                appearance: CircularSliderAppearance(
                                  customWidths: CustomSliderWidths(
                                    trackWidth: 4,
                                    progressBarWidth: 8,
                                    handlerSize: 8,
                                  ),
                                  customColors: CustomSliderColors(
                                    trackColor: theme.dividerColor,
                                    progressBarColor: colorScheme.primary,
                                    dotColor: colorScheme.primary,
                                    hideShadow: true,
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
                                      fontSize: 24,

                                    ),
                                  ),
                                  startAngle: 270,
                                  angleRange: 360,
                                  size: 200,
                                ),
                                onChange: (value) {
                                  setState(() {
                                    _sliderValue = value >= 71 ? 72 : value;
                                  });
                                },
                              ),
                              SizedBox(height: 20),
                              // Styled Add Member Input
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: theme.cardColor,
                                        borderRadius: BorderRadius.circular(36),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black12,
                                            blurRadius: 4,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: TextField(
                                        controller: _memberInputController,
                                        decoration: InputDecoration(
                                          hintText: 'Enter username to add',
                                          prefixText: '@',
                                          errorText: _usernameError ?? _memberLimitError,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                        ),
                                        style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  ElevatedButton(
                                    onPressed: _addMember,
                                    child: Text('Add'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colorScheme.onSurface,
                                      foregroundColor: colorScheme.surface,
                                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(36),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 20),
                              // Display Added Members
                              if (_members.isNotEmpty)
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: _members.map((username) {
                                    return Stack(
                                      children: [
                                        Column(
                                          children: [
                                            CircleAvatar(
                                              radius: 20,
                                              child: RandomAvatar(
                                                username,
                                                height: 40,
                                                width: 40,
                                              ),
                                            ),
                                            SizedBox(height: 5),
                                            Text(
                                              username,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: theme.textTheme.bodyMedium?.color,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: GestureDetector(
                                            onTap: () => _removeMember(username),
                                            child: CircleAvatar(
                                              radius: 8,
                                              backgroundColor: Colors.red,
                                              child: Icon(
                                                Icons.close,
                                                color: Colors.white,
                                                size: 10,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: (_isProcessing ||
                                    _members.isEmpty ||
                                    _groupNameController.text.trim().isEmpty)
                                    ? null
                                    : _createGroup,
                                child: _isProcessing
                                    ? CircularProgressIndicator(color: Colors.white)
                                    : Text('Create Group'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.onSurface,
                                  foregroundColor: colorScheme.surface,
                                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(36),
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
