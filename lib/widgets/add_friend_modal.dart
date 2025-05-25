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
import '../blocs/contacts/contacts_bloc.dart';
import '../services/sync_manager.dart';


class AddFriendModal extends StatefulWidget {
  final UserService userService;
  final RoomService roomService;
  final GroupsBloc groupsBloc;
  final VoidCallback? onGroupCreated;
  final VoidCallback? onContactAdded;

  const AddFriendModal({required this.userService, Key? key, required this.roomService, required this.groupsBloc, required this.onGroupCreated, this.onContactAdded}) : super(key: key);

  @override
  _AddFriendModalState createState() => _AddFriendModalState();
}


class _AddFriendModalState extends State<AddFriendModal> with TickerProviderStateMixin {
  // Add Contact variables
  final TextEditingController _controller = TextEditingController();
  bool _isProcessing = false;

  // Create Group variables
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _memberInputController = TextEditingController();
  List<String> _members = [];
  double _sliderValue = 12;
  bool _isForever = false;
  bool _isCustomDuration = false;
  DateTime? _customEndDate;
  String? _usernameError;
  String? _contactError;
  String? _matrixUserId = "";
  String? _friendQrCodeScan;

  // New variable for member limit error
  String? _memberLimitError;

  // Step-based group creation variables
  int _currentGroupStep = 0; // 0: Name, 1: Duration, 2: Members, 3: Summary

  late TabController _tabController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

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

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

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

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _controller.dispose();
    _tabController.dispose();
    _qrController?.dispose();
    _groupNameController.dispose();
    _memberInputController.dispose();
    super.dispose();
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

        final result = await this.widget.roomService.createRoomAndInviteContact(normalizedUserId);

        if (result) {
          // Get the room ID for the newly created direct room
          final myUserId = await widget.roomService.getMyUserId();
          if (myUserId != null) {
            // Find the direct room we just created
            final rooms = widget.roomService.client.rooms;
            final directRoom = rooms.where((room) {
              final name = room.name ?? '';
              return name == "Grid:Direct:$myUserId:$normalizedUserId" || 
                     name == "Grid:Direct:$normalizedUserId:$myUserId";
            }).firstOrNull;
            
            if (directRoom != null) {
              // Handle the new contact invite immediately using ContactsBloc
              try {
                final contactsBloc = context.read<ContactsBloc>();
                await contactsBloc.handleNewContactInvited(directRoom.id, normalizedUserId);
                print('AddFriendModal: Handled new contact invite via ContactsBloc');
              } catch (e) {
                print('AddFriendModal: Error calling ContactsBloc: $e');
              }
            }
          }
          
          // Clear _matrixUserId after successful use
          _matrixUserId = null;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Friend request sent to ${localpart(normalizedUserId)}.'),
                backgroundColor: Theme.of(context).colorScheme.primary,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
            // Trigger contact refresh callback
            widget.onContactAdded?.call();
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
      int durationInHours;
      
      if (_isForever) {
        durationInHours = 0;
      } else if (_isCustomDuration && _customEndDate != null) {
        final now = DateTime.now();
        final difference = _customEndDate!.difference(now);
        durationInHours = difference.inHours;
        if (durationInHours <= 0) durationInHours = 1; // Minimum 1 hour
      } else {
        durationInHours = _sliderValue.toInt();
      }

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

  // Step navigation methods for group creation
  void _nextGroupStep() {
    if (_currentGroupStep < 3) {
      setState(() {
        _currentGroupStep++;
      });
      _animateStepTransition();
    }
  }

  void _previousGroupStep() {
    if (_currentGroupStep > 0) {
      setState(() {
        _currentGroupStep--;
      });
      _animateStepTransition();
    }
  }

  void _animateStepTransition() {
    _slideController.reset();
    _slideController.forward();
  }

  bool _canProceedFromStep(int step) {
    switch (step) {
      case 0: // Group name
        return _groupNameController.text.trim().isNotEmpty;
      case 1: // Duration
        return true; // Always can proceed from duration
      case 2: // Members
        return _members.isNotEmpty;
      case 3: // Summary
        return true;
      default:
        return false;
    }
  }

  // Helper Methods for New UI
  Widget _buildModernCard({required Widget child, EdgeInsets? padding}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(24),
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

  Future<void> _showCustomDatePicker() async {
    final now = DateTime.now();
    final initialDate = _customEndDate ?? now.add(Duration(hours: 24));
    
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(Duration(days: 365)),
    );
    
    if (selectedDate != null) {
      final selectedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
      );
      
      if (selectedTime != null) {
        final customDateTime = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          selectedTime.hour,
          selectedTime.minute,
        );
        
        setState(() {
          _customEndDate = customDateTime;
          _isCustomDuration = true;
          _isForever = false;
        });
      }
    }
  }

  String _formatCustomDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);
    
    if (difference.inDays > 0) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} (${difference.inDays}d ${difference.inHours % 24}h)';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} (${difference.inHours}h ${difference.inMinutes % 60}m)';
    }
  }

  Widget _buildQuickDurationButton(String label, int hours, ColorScheme colorScheme) {
    bool isSelected;
    if (label == 'Custom') {
      isSelected = _isCustomDuration;
    } else {
      isSelected = !_isCustomDuration && (_sliderValue == hours || (hours == 0 && _isForever));
    }
    
    return GestureDetector(
      onTap: () {
        if (label == 'Custom') {
          _showCustomDatePicker();
        } else {
          setState(() {
            _sliderValue = hours.toDouble();
            _isForever = hours == 0;
            _isCustomDuration = false;
            _customEndDate = null;
          });
        }
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

  // New Modern Add Contact UI Components
  Widget _buildContactHeader() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _buildModernCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.person_add,
              color: colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Contact',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Send a friend request to start sharing',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactUsernameInput() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _buildModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Username',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: isCustomHomeserver() ? 'john:homeserver.io' : 'Enter username',
              prefixText: '@',
              errorText: _contactError,
              filled: true,
              fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outline.withOpacity(0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.primary,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.error,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          if (_contactError == null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: colorScheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Secure location sharing begins once accepted',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
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
    );
  }

  Widget _buildContactQRScannerCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _buildModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.qr_code_scanner,
                  color: colorScheme.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Add',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Scan a user\'s QR code',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _scanQRCode,
                icon: Icon(
                  Icons.qr_code_scanner,
                  size: 18,
                  color: colorScheme.primary,
                ),
                label: Text(
                  'Scan',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  backgroundColor: colorScheme.primary.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactQRScanner() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _buildModernCard(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {
                  _qrController?.pauseCamera();
                  setState(() {
                    _isScanning = false;
                  });
                },
                icon: Icon(
                  Icons.arrow_back,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Scan QR Code',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.2),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: QrScannerOverlayShape(
                borderColor: colorScheme.primary,
                borderRadius: 12,
                borderLength: 30,
                borderWidth: 4,
                cutOutSize: 250,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.onSurface.withOpacity(0.6),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Point your camera at a user\'s QR code to add them instantly',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactActionButtons() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.onSurface,
                side: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _addContact,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isProcessing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: colorScheme.onPrimary,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Send Request',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Step-based Group Creation UI Components
  Widget _buildStepHeader({
    required String title,
    required String subtitle,
    Widget? illustration,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Column(
      children: [
        if (illustration != null) ...[
          illustration,
          const SizedBox(height: 24),
        ],
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isActive = index <= _currentGroupStep;
        final isCurrent = index == _currentGroupStep;
        
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isCurrent ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive 
                      ? colorScheme.primary 
                      : colorScheme.outline.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              if (index < 3) SizedBox(width: 8),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepNavigationButtons({
    required String? nextText,
    required VoidCallback? onNext,
    String? backText,
    VoidCallback? onBack,
    bool isLoading = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          if (onBack != null) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: isLoading ? null : onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.onSurface,
                  side: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(backText ?? 'Back'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: onBack != null ? 1 : 2,
            child: ElevatedButton(
              onPressed: isLoading ? null : onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: colorScheme.onPrimary,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          nextText ?? 'Next',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (nextText == null || nextText.toLowerCase().contains('next')) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward, size: 18),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Step 0: Group Name
  Widget _buildGroupNameStep() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SlideTransition(
      position: _slideAnimation,
      child: _buildModernCard(
        child: Column(
          children: [
            _buildStepHeader(
              title: 'Create Group',
              subtitle: 'Choose a memorable name for your group',
              illustration: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colorScheme.primary.withOpacity(0.1),
                      colorScheme.primary.withOpacity(0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.3, 0.7, 1.0],
                  ),
                ),
                child: Icon(
                  Icons.group_add,
                  size: 40,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _groupNameController,
              maxLength: 14,
              onChanged: (value) => setState(() {}), // Trigger rebuild for button state
              decoration: InputDecoration(
                labelText: 'Group Name',
                hintText: 'Enter group name...',
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                counterText: '',
              ),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: colorScheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Group names are visible to all members',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
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
    );
  }

  // Step 1: Duration
  Widget _buildGroupDurationStep() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SlideTransition(
      position: _slideAnimation,
      child: _buildModernCard(
        child: Column(
          children: [
            _buildStepHeader(
              title: 'Set Duration',
              subtitle: 'How long should the group last?',
              illustration: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colorScheme.secondary.withOpacity(0.1),
                      colorScheme.secondary.withOpacity(0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.3, 0.7, 1.0],
                  ),
                ),
                child: Icon(
                  Icons.schedule,
                  size: 40,
                  color: colorScheme.secondary,
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Duration options in a clean grid
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildQuickDurationButton('12h', 12, colorScheme),
                _buildQuickDurationButton('24h', 24, colorScheme),
                _buildQuickDurationButton('72h', 72, colorScheme),
                _buildQuickDurationButton('∞', 0, colorScheme),
                _buildQuickDurationButton('Custom', -1, colorScheme),
              ],
            ),
            
            // Show selected custom duration info
            if (_isCustomDuration && _customEndDate != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Custom End Time',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatCustomDateTime(_customEndDate!),
                            style: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.7),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _showCustomDatePicker,
                      child: Text(
                        'Change',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
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
    );
  }

  // Step 2: Add Members
  Widget _buildGroupMembersStep() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SlideTransition(
      position: _slideAnimation,
      child: _buildModernCard(
        child: Column(
          children: [
            _buildStepHeader(
              title: 'Add Members',
              subtitle: 'Invite up to 5 friends to your group',
              illustration: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colorScheme.tertiary.withOpacity(0.1),
                      colorScheme.tertiary.withOpacity(0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.3, 0.7, 1.0],
                  ),
                ),
                child: Icon(
                  Icons.people,
                  size: 40,
                  color: colorScheme.tertiary,
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Add Member Input
            TextField(
              controller: _memberInputController,
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: isCustomHomeserver() ? 'john:homeserver.io' : 'Enter username...',
                prefixText: '@',
                errorText: _usernameError ?? _memberLimitError,
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.error,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            // Add Member Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _addMember,
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Add Member'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.secondary,
                  foregroundColor: colorScheme.onSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Members List
            if (_members.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.2),
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
                        const SizedBox(width: 8),
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
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _members.map((username) => _buildMemberCard(username, colorScheme)).toList(),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.people_outline,
                      color: colorScheme.onSurface.withOpacity(0.4),
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No members added yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface.withOpacity(0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
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
    );
  }

  // Step 3: Summary
  Widget _buildGroupSummaryStep() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String durationText;
    if (_isForever) {
      durationText = 'Permanent';
    } else if (_isCustomDuration && _customEndDate != null) {
      durationText = 'Until ${_formatCustomDateTime(_customEndDate!)}';
    } else {
      durationText = '${_sliderValue.toInt()} hours';
    }

    return SlideTransition(
      position: _slideAnimation,
      child: _buildModernCard(
        child: Column(
          children: [
            _buildStepHeader(
              title: 'Review & Create',
              subtitle: 'Check your group details before creating',
              illustration: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.green.withOpacity(0.1),
                      Colors.green.withOpacity(0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.3, 0.7, 1.0],
                  ),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 40,
                  color: Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            // Summary Cards
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.1),
                ),
              ),
              child: Column(
                children: [
                  _buildSummaryRow(
                    icon: Icons.group,
                    label: 'Group Name',
                    value: _groupNameController.text.trim(),
                    colorScheme: colorScheme,
                  ),
                  const Divider(height: 24),
                  _buildSummaryRow(
                    icon: Icons.schedule,
                    label: 'Duration',
                    value: durationText,
                    colorScheme: colorScheme,
                  ),
                  const Divider(height: 24),
                  _buildSummaryRow(
                    icon: Icons.people,
                    label: 'Members',
                    value: '${_members.length} invited',
                    colorScheme: colorScheme,
                  ),
                ],
              ),
            ),
            
            if (_members.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Members to invite:',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _members.map((username) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: colorScheme.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          '@$username',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: colorScheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepBasedGroupTab() {
    return Column(
      children: [
        // Step indicator
        Padding(
          padding: const EdgeInsets.all(24),
          child: _buildStepIndicator(),
        ),
        
        // Step content with generous padding
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: _getCurrentStepWidget(),
          ),
        ),
        
        // Navigation buttons
        _buildStepNavigationButtons(
          nextText: _currentGroupStep == 3 ? 'Create Group' : null,
          onNext: _currentGroupStep == 3 
              ? (_canProceedFromStep(_currentGroupStep) ? _createGroup : null)
              : (_canProceedFromStep(_currentGroupStep) ? _nextGroupStep : null),
          backText: _currentGroupStep == 0 ? 'Cancel' : null,
          onBack: _currentGroupStep == 0 
              ? () => Navigator.of(context).pop()
              : _previousGroupStep,
          isLoading: _isProcessing,
        ),
      ],
    );
  }

  Widget _getCurrentStepWidget() {
    switch (_currentGroupStep) {
      case 0:
        return _buildGroupNameStep();
      case 1:
        return _buildGroupDurationStep();
      case 2:
        return _buildGroupMembersStep();
      case 3:
        return _buildGroupSummaryStep();
      default:
        return _buildGroupNameStep();
    }
  }

  Widget _buildModernAddContactTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        children: [
          _buildContactHeader(),
          if (_isScanning) _buildContactQRScanner() else ...[
            _buildContactUsernameInput(),
            _buildContactQRScannerCard(),
          ],
          if (!_isScanning) _buildContactActionButtons(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.background,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modern handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outline.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Tabs with better spacing
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: TabBar(
                  controller: _tabController,
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: colorScheme.onSurface.withOpacity(0.6),
                  indicatorColor: colorScheme.primary,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: [
                    Tab(text: 'Add Contact'),
                    Tab(text: 'Create Group'),
                  ],
                ),
              ),
              
              // Tab views with flexible height
              Flexible(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Add Contact Tab - Modern Design
                    _buildModernAddContactTab(),
                    // Create Group Tab - Step-based Design
                    _buildStepBasedGroupTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}