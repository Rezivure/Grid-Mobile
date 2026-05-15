// add_friend_modal.dart
//
// Restyled to match Grid mobile redesign §5.10 "Add friend (hub)" and §5.11
// "Scan QR". All existing logic — QR scanning, share-link generation, handle
// lookup, invite-sending, error handling, group creation — is preserved.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:provider/provider.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/services/room_service.dart';

import '../blocs/groups/groups_bloc.dart';
import '../blocs/groups/groups_event.dart';
import '../blocs/contacts/contacts_bloc.dart';
import '../services/sync_manager.dart';
import '../styles/tokens.dart';
import 'grid/grid_button.dart';
import 'grid/grid_mono.dart';


class AddFriendModal extends StatefulWidget {
  final UserService userService;
  final RoomService roomService;
  final GroupsBloc groupsBloc;
  final VoidCallback? onGroupCreated;
  final VoidCallback? onContactAdded;

  const AddFriendModal({
    required this.userService,
    Key? key,
    required this.roomService,
    required this.groupsBloc,
    required this.onGroupCreated,
    this.onContactAdded,
  }) : super(key: key);

  @override
  _AddFriendModalState createState() => _AddFriendModalState();
}

/// Sub-views inside the Add Friend hub. The hub view itself shows the user's
/// QR + the three method rows. Other views slot in to preserve all flows.
enum _AddFriendView { hub, scan, handle, groupCreate }

class _AddFriendModalState extends State<AddFriendModal>
    with TickerProviderStateMixin {
  // ── Add Contact state ────────────────────────────────────────────────
  final TextEditingController _controller = TextEditingController();
  bool _isProcessing = false;
  String? _contactError;
  String? _matrixUserId = "";
  String? _friendQrCodeScan;

  // The currently visible sub-view.
  _AddFriendView _view = _AddFriendView.hub;

  // ── User identity (for the hero QR card) ─────────────────────────────
  String? _myUserId;
  String? _myHandle; // "@anya.beech" or full matrix id on custom HS

  // ── Create Group state (preserved unchanged) ─────────────────────────
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _memberInputController = TextEditingController();
  List<String> _members = [];
  double _sliderValue = 12;
  bool _isForever = false;
  bool _isCustomDuration = false;
  DateTime? _customEndDate;
  String? _usernameError;
  String? _memberLimitError;
  int _currentGroupStep = 0; // 0: Name, 1: Duration, 2: Members, 3: Summary

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // ── QR scan state ────────────────────────────────────────────────────
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _qrController;
  bool hasScanned = false;
  bool _flashOn = false;

  // Animated scan line for the camera viewfinder.
  late AnimationController _scanLineController;

  @override
  void initState() {
    super.initState();

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

    _scanLineController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();

    _controller.addListener(() {
      if (_contactError != null) {
        setState(() {
          _contactError = null;
        });
      }
      if (_controller.text.isNotEmpty) {
        _matrixUserId = null;
      }
    });

    _memberInputController.addListener(() {
      if (_memberLimitError != null) {
        setState(() {
          _memberLimitError = null;
        });
      }
    });

    _fadeController.forward();
    _slideController.forward();

    _loadMyIdentity();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scanLineController.dispose();
    _controller.dispose();
    _qrController?.dispose();
    _groupNameController.dispose();
    _memberInputController.dispose();
    super.dispose();
  }

  Future<void> _loadMyIdentity() async {
    final id = widget.roomService.getMyUserId();
    if (id == null) return;
    final isCustom = isCustomHomeserver();
    if (mounted) {
      setState(() {
        _myUserId = id;
        _myHandle = isCustom ? id : '@${utils.localpart(id)}';
      });
    }
  }

  bool isCustomHomeserver() {
    final homeserver = widget.roomService.getMyHomeserver();
    return utils.isCustomHomeserver(homeserver);
  }

  // ─────────────────────────────────────────────────────────────────────
  // Add contact / friend logic (preserved verbatim from original)
  // ─────────────────────────────────────────────────────────────────────
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

    // Check if this is from QR scan (already has @ prefix)
    if (_friendQrCodeScan != null && normalizedUserId.startsWith('@')) {
      // QR code contains full matrix ID
      if (!isCustomServer) {
        // For default homeserver, extract just the localpart and rebuild
        final localpart =
            normalizedUserId.split(':')[0].replaceFirst('@', '');
        final homeserver = widget.roomService
            .getMyHomeserver()
            .replaceFirst('https://', '');
        normalizedUserId = '@$localpart:$homeserver';
      }
      // For custom homeserver, use as-is
    } else {
      // Manual input from text field
      if (isCustomServer) {
        // For custom homeservers, expect full matrix ID without @ prefix
        // (since @ is already shown as prefix in the input field)
        if (!normalizedUserId.contains(':')) {
          setState(() {
            _contactError =
                'Please enter full Matrix ID (e.g., user:domain.com)';
            _isProcessing = false;
          });
          return;
        }
        normalizedUserId = '@$normalizedUserId';
      } else {
        // For default homeserver, just add local part
        final homeserver = widget.roomService
            .getMyHomeserver()
            .replaceFirst('https://', '');
        normalizedUserId = '@$normalizedUserId:$homeserver';
      }
    }

    if (normalizedUserId.isNotEmpty) {
      if (mounted) {
        setState(() {
          _isProcessing = true;
          _contactError = null; // Reset error before trying to add
        });
      }
      try {
        print('AddFriendModal: Checking if user exists: $normalizedUserId');
        bool userExists =
            await widget.userService.userExists(normalizedUserId);
        if (!userExists) {
          if (mounted) {
            setState(() {
              _contactError = 'Invalid username: @$inputText';
              _isProcessing = false;
            });
          }
          return;
        }

        final result = await widget.roomService
            .createRoomAndInviteContact(normalizedUserId);

        if (result) {
          // Get the room ID for the newly created direct room
          final myUserId = widget.roomService.getMyUserId();
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
                await contactsBloc.handleNewContactInvited(
                    directRoom.id, normalizedUserId);
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
                content: Text(
                    'Friend request sent to ${utils.localpart(normalizedUserId)}.'),
                backgroundColor: GridTokens.mint,
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

  // ─────────────────────────────────────────────────────────────────────
  // QR scanning (logic preserved; chrome restyled)
  // ─────────────────────────────────────────────────────────────────────
  void _openScanner() {
    hasScanned = false;
    setState(() {
      _view = _AddFriendView.scan;
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
          controller.pauseCamera();
          setState(() {
            _matrixUserId = scannedUserId;
            // For custom homeservers, preserve the full matrix ID (without @)
            // For default homeserver, extract just the localpart
            if (isCustomHomeserver() && scannedUserId.contains(':')) {
              _controller.text = scannedUserId.replaceFirst('@', '');
            } else {
              _controller.text =
                  scannedUserId.split(":").first.replaceFirst('@', '');
            }
            _friendQrCodeScan = scannedUserId;
            _view = _AddFriendView.hub;
            _addContact();
          });
        } else {
          print('QR Code data is empty');
        }
      }
    });
  }

  void _toggleFlash() async {
    try {
      await _qrController?.toggleFlash();
      final flash = await _qrController?.getFlashStatus();
      if (mounted) {
        setState(() {
          _flashOn = flash ?? !_flashOn;
        });
      }
    } catch (_) {
      // toggleFlash can throw on devices without flash; ignore.
    }
  }

  void _closeScanner() {
    _qrController?.pauseCamera();
    setState(() {
      _view = _AddFriendView.hub;
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // Group-creation logic (preserved verbatim; reachable via overflow)
  // ─────────────────────────────────────────────────────────────────────
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

    String username = inputUsername.startsWith('@')
        ? inputUsername.substring(1)
        : inputUsername;

    if (_members.contains(username)) {
      setState(() {
        _usernameError = 'User already added.';
      });
      return;
    }

    var usernameLowercase = username.toLowerCase();
    var fullMatrixId = usernameLowercase;
    final homeserver =
        widget.roomService.getMyHomeserver().replaceFirst('https://', '');
    bool isCustomServer = isCustomHomeserver();

    if (isCustomServer) {
      if (!usernameLowercase.contains(':')) {
        setState(() {
          _usernameError =
              'Please enter full Matrix ID (e.g., user:domain.com)';
        });
        return;
      }
      fullMatrixId = '@$usernameLowercase';
    } else {
      fullMatrixId = '@$usernameLowercase:$homeserver';
    }

    final doesExist = await widget.userService.userExists(fullMatrixId);
    final isSelf = widget.roomService.getMyUserId() == fullMatrixId;

    if (!doesExist || isSelf) {
      setState(() {
        _usernameError = 'Invalid username: @$username';
      });
    } else {
      setState(() {
        _members.add(username);
        _usernameError = null;
        _memberLimitError = null;
        _memberInputController.clear();
      });
    }
  }

  void _removeMember(String username) {
    setState(() {
      _members.remove(username);
      if (_memberLimitError != null && _members.length < 5) {
        _memberLimitError = null;
      }
    });
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty || _members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a group name and add members.')),
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
        if (durationInHours <= 0) durationInHours = 1;
      } else {
        durationInHours = _sliderValue.toInt();
      }

      final normalizedMembers = _members.map((username) {
        print('Passing member to room service: $username');
        return username;
      }).toList();

      print('Creating group with members: $normalizedMembers');

      final roomId = await widget.roomService
          .createGroup(groupName, normalizedMembers, durationInHours);

      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 500));

        final syncManager = Provider.of<SyncManager>(context, listen: false);
        await syncManager.handleNewGroupCreation(roomId);

        widget.onGroupCreated?.call();
        widget.groupsBloc.add(RefreshGroups());

        Navigator.pop(context);

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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Group created successfully',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
            backgroundColor: GridTokens.mint,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(
              bottom: 20,
              left: 20,
              right: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
            elevation: 6,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = 'Error creating group';
        if (e.toString().contains('does not exist') ||
            e.toString().contains('not found')) {
          errorMsg = 'One or more users could not be found';
        } else if (e.toString().contains('permission')) {
          errorMsg = 'Permission denied to create group';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(errorMsg)),
              ],
            ),
            backgroundColor: GridTokens.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
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

  void _nextGroupStep() {
    if (_currentGroupStep < 3) {
      setState(() {
        _currentGroupStep++;
      });
      _slideController.reset();
      _slideController.forward();
    }
  }

  void _previousGroupStep() {
    if (_currentGroupStep > 0) {
      setState(() {
        _currentGroupStep--;
      });
      _slideController.reset();
      _slideController.forward();
    }
  }

  bool _canProceedFromStep(int step) {
    switch (step) {
      case 0:
        return _groupNameController.text.trim().isNotEmpty;
      case 1:
        return true;
      case 2:
        return _members.isNotEmpty;
      case 3:
        return true;
      default:
        return false;
    }
  }

  Future<void> _showCustomDatePicker() async {
    final now = DateTime.now();
    final initialDate = _customEndDate ?? now.add(const Duration(hours: 24));

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
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

  // ─────────────────────────────────────────────────────────────────────
  // Share invite link (logic preserved)
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _shareInviteLink() async {
    try {
      final myUserId = widget.roomService.getMyUserId();
      if (myUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to get your username'),
            backgroundColor: GridTokens.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        return;
      }

      final localpart = utils.localpart(myUserId);

      final message =
          'Join me on Grid! Download it at https://get.grid.lat and send @$localpart a friend request!';

      await Share.share(
        message,
        subject: 'Join me on Grid: Private Location Sharing!',
      );
    } catch (e) {
      print('Error sharing invite link: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to share invite'),
            backgroundColor: GridTokens.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      color: Colors.transparent,
      child: AnimatedPadding(
        padding: EdgeInsets.only(bottom: bottomInset),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: Container(
          decoration: const BoxDecoration(
            color: GridTokens.bg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(GridTokens.r2Xl),
              topRight: Radius.circular(GridTokens.r2Xl),
            ),
          ),
          child: SafeArea(
            top: false,
            child: _buildCurrentView(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_view) {
      case _AddFriendView.scan:
        return _buildScanView();
      case _AddFriendView.handle:
        return _buildHandleView();
      case _AddFriendView.groupCreate:
        return _buildGroupCreateView();
      case _AddFriendView.hub:
        return _buildHubView();
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // §5.10  Add friend (hub)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildHubView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTopBar(
          title: 'Add a friend',
          onClose: () => Navigator.of(context).pop(),
          trailing: IconButton(
            icon: const Icon(Icons.group_add_outlined,
                color: GridTokens.text2, size: 22),
            tooltip: 'Create a group',
            onPressed: () {
              setState(() {
                _currentGroupStep = 0;
                _view = _AddFriendView.groupCreate;
              });
              _slideController.reset();
              _slideController.forward();
            },
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildQrHeroCard(),
                  const SizedBox(height: 24),
                  _buildOrDivider(),
                  const SizedBox(height: 20),
                  _buildMethodRow(
                    icon: Icons.qr_code_scanner_rounded,
                    title: "Scan a friend's code",
                    subtitle: 'Open camera and point',
                    onTap: _openScanner,
                  ),
                  const SizedBox(height: 10),
                  _buildMethodRow(
                    icon: Icons.link_rounded,
                    title: 'Share an invite link',
                    subtitle: 'Expires in 24 hours',
                    onTap: _shareInviteLink,
                  ),
                  const SizedBox(height: 10),
                  _buildMethodRow(
                    icon: Icons.search_rounded,
                    title: 'Type a handle',
                    subtitle: isCustomHomeserver()
                        ? '@user:homeserver.io'
                        : '@username on this server',
                    onTap: () {
                      setState(() {
                        _view = _AddFriendView.handle;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  _buildSafetyTip(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // QR hero card — surface gradient, white tile, mono caption, handle.
  Widget _buildQrHeroCard() {
    final handle = _myHandle ?? '@…';
    final qrData = _myUserId ?? handle;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GridTokens.surface2, GridTokens.surface],
        ),
        borderRadius: BorderRadius.circular(GridTokens.rXl),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Column(
        children: [
          // White rounded-16 QR tile with center Grid-mark.
          LayoutBuilder(builder: (context, constraints) {
            final tile =
                (constraints.maxWidth * 0.62).clamp(180.0, 240.0).toDouble();
            return Container(
              width: tile,
              height: tile,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: tile - 28,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                  // Center Grid-mark badge.
                  Container(
                    width: (tile - 28) * 0.16,
                    height: (tile - 28) * 0.16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: (tile - 28) * 0.10,
                      height: (tile - 28) * 0.10,
                      decoration: const BoxDecoration(
                        color: GridTokens.mint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 12,
                        color: Color(0xFF04201A),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 18),
          GridMono(
            'YOUR HANDLE',
            size: 10,
            color: GridTokens.text3,
            letterSpacing: 0.12,
          ),
          const SizedBox(height: 6),
          Text(
            handle,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.01,
              color: GridTokens.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrDivider() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Container(height: 1, color: GridTokens.hairline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridMono('OR',
              size: 10, color: GridTokens.text3, letterSpacing: 0.16),
        ),
        Expanded(child: Container(height: 1, color: GridTokens.hairline)),
      ],
    );
  }

  Widget _buildMethodRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: GridTokens.surface,
            borderRadius: BorderRadius.circular(GridTokens.rLg),
            border: Border.all(color: GridTokens.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: GridTokens.surface2,
                  borderRadius: BorderRadius.circular(GridTokens.rMd),
                  border: Border.all(color: GridTokens.hairline),
                ),
                child: Icon(icon, color: GridTokens.text, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: GridTokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: GridTokens.text3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: GridTokens.text3, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSafetyTip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: GridTokens.surface,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined,
              color: GridTokens.mint, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 12.5,
                  height: 1.45,
                  color: GridTokens.text2,
                ),
                children: const [
                  TextSpan(text: 'Nothing is shared until '),
                  TextSpan(
                    text: 'both of you',
                    style: TextStyle(
                      color: GridTokens.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ' confirm. Verify with a 4-digit safety number.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Shared top bar
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildTopBar({
    required String title,
    required VoidCallback onClose,
    Widget? trailing,
    Color? foreground,
    bool transparent = false,
  }) {
    final fg = foreground ?? GridTokens.text;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.of(context).padding.top + 8,
        12,
        8,
      ),
      child: Row(
        children: [
          _topBarButton(
            icon: Icons.close_rounded,
            onTap: onClose,
            fg: fg,
            transparent: transparent,
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.01,
                  color: fg,
                ),
              ),
            ),
          ),
          if (trailing != null)
            SizedBox(width: 44, height: 44, child: Center(child: trailing))
          else
            const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _topBarButton({
    required IconData icon,
    required VoidCallback onTap,
    Color fg = GridTokens.text,
    bool transparent = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: transparent
                ? Colors.black.withValues(alpha: 0.32)
                : GridTokens.surface,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(
              color: transparent
                  ? Colors.white.withValues(alpha: 0.16)
                  : GridTokens.hairline,
            ),
          ),
          child: Icon(icon, color: fg, size: 20),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // §5.11  Scan QR (full-screen camera with overlay)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildScanView() {
    final size = MediaQuery.of(context).size;
    const viewfinder = 240.0;
    return SizedBox(
      width: double.infinity,
      height: size.height * 0.92,
      child: Stack(
        children: [
          // Camera feed.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(GridTokens.r2Xl),
                topRight: Radius.circular(GridTokens.r2Xl),
              ),
              child: QRView(
                key: qrKey,
                onQRViewCreated: _onQRViewCreated,
                overlay: QrScannerOverlayShape(
                  borderColor: Colors.transparent,
                  borderWidth: 0,
                  cutOutSize: viewfinder,
                  overlayColor: Colors.black.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          // Mint corner brackets + animated scan line, perfectly centered.
          Center(
            child: SizedBox(
              width: viewfinder,
              height: viewfinder,
              child: Stack(
                children: [
                  // Four mint corner brackets.
                  ..._buildCornerBrackets(),
                  // Animated horizontal scan line.
                  AnimatedBuilder(
                    animation: _scanLineController,
                    builder: (context, _) {
                      final t = _scanLineController.value;
                      return Positioned(
                        left: 0,
                        right: 0,
                        top: (viewfinder - 2) * t,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                GridTokens.mint.withValues(alpha: 0.0),
                                GridTokens.mint,
                                GridTokens.mint.withValues(alpha: 0.0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    GridTokens.mint.withValues(alpha: 0.55),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // Top bar (transparent over camera).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(
              title: 'Scan a code',
              onClose: _closeScanner,
              transparent: true,
              foreground: Colors.white,
              trailing: _topBarButton(
                icon: _flashOn
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
                onTap: _toggleFlash,
                fg: Colors.white,
                transparent: true,
              ),
            ),
          ),
          // Bottom hint pill + secondary controls.
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: GridMono(
                    'HOLD STEADY · CENTER THE CODE',
                    size: 10,
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 0.14,
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GridButton(
                    label: 'Show my code instead',
                    icon: Icons.qr_code_rounded,
                    style: GridButtonStyle.secondary,
                    onPressed: _closeScanner,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () {
                    _closeScanner();
                    setState(() {
                      _view = _AddFriendView.handle;
                    });
                  },
                  child: Text(
                    'Or paste a Grid link',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: GridTokens.mint,
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

  List<Widget> _buildCornerBrackets() {
    const length = 26.0;
    const thickness = 3.0;
    const radius = 2.0;
    Widget corner({required Alignment alignment, required bool horizontal}) {
      return Align(
        alignment: alignment,
        child: Container(
          width: horizontal ? length : thickness,
          height: horizontal ? thickness : length,
          decoration: BoxDecoration(
            color: GridTokens.mint,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
    }

    return [
      // Top-left
      corner(alignment: Alignment.topLeft, horizontal: true),
      corner(alignment: Alignment.topLeft, horizontal: false),
      // Top-right
      corner(alignment: Alignment.topRight, horizontal: true),
      corner(alignment: Alignment.topRight, horizontal: false),
      // Bottom-left
      corner(alignment: Alignment.bottomLeft, horizontal: true),
      corner(alignment: Alignment.bottomLeft, horizontal: false),
      // Bottom-right
      corner(alignment: Alignment.bottomRight, horizontal: true),
      corner(alignment: Alignment.bottomRight, horizontal: false),
    ];
  }

  // ─────────────────────────────────────────────────────────────────────
  // Handle-input sub-view (reachable from "Type a handle")
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildHandleView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTopBar(
          title: 'Add by handle',
          onClose: () {
            setState(() {
              _view = _AddFriendView.hub;
              _contactError = null;
              _controller.clear();
              _friendQrCodeScan = null;
            });
          },
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: GridTokens.surface,
                    borderRadius: BorderRadius.circular(GridTokens.rLg),
                    border: Border.all(
                      color: _contactError != null
                          ? GridTokens.danger
                          : GridTokens.hairline,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GridMono(
                        'HANDLE',
                        size: 10,
                        color: GridTokens.text3,
                        letterSpacing: 0.14,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '@',
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: GridTokens.text3,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _addContact(),
                              cursorColor: GridTokens.mint,
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: GridTokens.text,
                              ),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                hintText: isCustomHomeserver()
                                    ? 'user:homeserver.io'
                                    : 'username',
                                hintStyle: GoogleFonts.getFont(
                                  'Geist',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: GridTokens.text4,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_contactError != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: GridTokens.danger, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _contactError!,
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: GridTokens.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _buildSafetyTip(),
                const SizedBox(height: 20),
                GridButton(
                  label: 'Send friend request',
                  icon: Icons.send_rounded,
                  onPressed: _isProcessing ? null : _addContact,
                ),
                if (_isProcessing) ...[
                  const SizedBox(height: 14),
                  const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: GridTokens.mint,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Group creation sub-view (logic preserved; lightly restyled with tokens)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildGroupCreateView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTopBar(
          title: 'Create a group',
          onClose: () {
            setState(() {
              _view = _AddFriendView.hub;
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: _buildStepIndicator(),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SlideTransition(
              position: _slideAnimation,
              child: _buildGroupStepContent(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: GridButton(
                  label: _currentGroupStep == 0 ? 'Cancel' : 'Back',
                  style: GridButtonStyle.secondary,
                  onPressed: _isProcessing
                      ? null
                      : () {
                          if (_currentGroupStep == 0) {
                            setState(() {
                              _view = _AddFriendView.hub;
                            });
                          } else {
                            _previousGroupStep();
                          }
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GridButton(
                  label: _currentGroupStep == 3 ? 'Create group' : 'Next',
                  icon: _currentGroupStep == 3
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: _isProcessing
                      ? null
                      : (_currentGroupStep == 3
                          ? (_canProceedFromStep(_currentGroupStep)
                              ? _createGroup
                              : null)
                          : (_canProceedFromStep(_currentGroupStep)
                              ? _nextGroupStep
                              : null)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isActive = index <= _currentGroupStep;
        final isCurrent = index == _currentGroupStep;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isCurrent ? 24 : 8,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? GridTokens.mint : GridTokens.hairlineStrong,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildGroupStepContent() {
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

  Widget _buildGroupNameStep() {
    return _buildGroupCard(
      title: 'Name the group',
      subtitle: 'Choose a memorable name for your group',
      child: TextField(
        controller: _groupNameController,
        maxLength: 14,
        onChanged: (value) => setState(() {}),
        cursorColor: GridTokens.mint,
        style: GoogleFonts.getFont(
          'Geist',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: GridTokens.text,
        ),
        decoration: _groupInputDecoration(
          hintText: 'Group name',
          counterText: '',
        ),
      ),
    );
  }

  Widget _buildGroupDurationStep() {
    return _buildGroupCard(
      title: 'Set duration',
      subtitle: 'How long should the group last?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildDurationChip('12h', 12),
              _buildDurationChip('24h', 24),
              _buildDurationChip('72h', 72),
              _buildDurationChip('Forever', 0),
              _buildDurationChip('Custom', -1),
            ],
          ),
          if (_isCustomDuration && _customEndDate != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: GridTokens.mintFaint,
                borderRadius: BorderRadius.circular(GridTokens.rMd),
                border: Border.all(color: GridTokens.mintSoft),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      color: GridTokens.mint, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom end time',
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: GridTokens.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatCustomDateTime(_customEndDate!),
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 12,
                            color: GridTokens.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _showCustomDatePicker,
                    child: Text(
                      'Change',
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: GridTokens.mint,
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

  Widget _buildDurationChip(String label, int hours) {
    bool isSelected;
    if (label == 'Custom') {
      isSelected = _isCustomDuration;
    } else {
      isSelected = !_isCustomDuration &&
          (_sliderValue == hours || (hours == 0 && _isForever));
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? GridTokens.mintFaint : GridTokens.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? GridTokens.mint : GridTokens.hairline,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? GridTokens.mint : GridTokens.text,
          ),
        ),
      ),
    );
  }

  Widget _buildGroupMembersStep() {
    return _buildGroupCard(
      title: 'Add members',
      subtitle: 'Invite up to 5 friends',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _memberInputController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addMember(),
            cursorColor: GridTokens.mint,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: GridTokens.text,
            ),
            decoration: _groupInputDecoration(
              hintText: isCustomHomeserver()
                  ? 'user:homeserver.io'
                  : 'username',
              prefixText: '@',
              errorText: _usernameError ?? _memberLimitError,
              suffix: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _addMember,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.add_circle_rounded,
                        color: GridTokens.mint, size: 24),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_members.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GridTokens.surface,
                borderRadius: BorderRadius.circular(GridTokens.rMd),
                border: Border.all(color: GridTokens.hairline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline_rounded,
                      color: GridTokens.text3, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'No members added yet',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: GridTokens.text2,
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _members
                  .map((username) => _buildMemberChip(username))
                  .toList(),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GridMono(
              '${_members.length}/5 MEMBERS',
              size: 10,
              color: GridTokens.text3,
              letterSpacing: 0.14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberChip(String username) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: GridTokens.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '@${username.toLowerCase()}',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: GridTokens.text,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _removeMember(username),
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GridTokens.dangerSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: GridTokens.danger, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSummaryStep() {
    String durationText;
    if (_isForever) {
      durationText = 'Permanent';
    } else if (_isCustomDuration && _customEndDate != null) {
      durationText = 'Until ${_formatCustomDateTime(_customEndDate!)}';
    } else {
      durationText = '${_sliderValue.toInt()} hours';
    }

    return _buildGroupCard(
      title: 'Review',
      subtitle: 'Check the details before creating',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryRow(
              icon: Icons.group_rounded,
              label: 'GROUP NAME',
              value: _groupNameController.text.trim()),
          const SizedBox(height: 14),
          _buildSummaryRow(
              icon: Icons.schedule_rounded,
              label: 'DURATION',
              value: durationText),
          const SizedBox(height: 14),
          _buildSummaryRow(
              icon: Icons.people_alt_rounded,
              label: 'MEMBERS',
              value: '${_members.length} invited'),
          if (_members.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _members
                  .map(
                    (username) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: GridTokens.mintFaint,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: GridTokens.mintSoft),
                      ),
                      child: Text(
                        '@$username',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: GridTokens.mint,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GridTokens.surface,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GridTokens.surface2,
              borderRadius: BorderRadius.circular(GridTokens.rMd),
              border: Border.all(color: GridTokens.hairline),
            ),
            child: Icon(icon, color: GridTokens.mint, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GridMono(label,
                    size: 10,
                    color: GridTokens.text3,
                    letterSpacing: 0.14),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? '—' : value,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GridTokens.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GridTokens.surface,
        borderRadius: BorderRadius.circular(GridTokens.rXl),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.01,
              color: GridTokens.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              color: GridTokens.text3,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  InputDecoration _groupInputDecoration({
    required String hintText,
    String? prefixText,
    String? errorText,
    Widget? suffix,
    String? counterText,
  }) {
    final base = OutlineInputBorder(
      borderRadius: BorderRadius.circular(GridTokens.rMd),
      borderSide: const BorderSide(color: GridTokens.hairline),
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.getFont(
        'Geist',
        fontSize: 15,
        color: GridTokens.text4,
      ),
      prefixText: prefixText,
      prefixStyle: GoogleFonts.getFont(
        'Geist',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: GridTokens.text3,
      ),
      errorText: errorText,
      errorStyle: GoogleFonts.getFont(
        'Geist',
        fontSize: 12,
        color: GridTokens.danger,
      ),
      filled: true,
      fillColor: GridTokens.bg,
      counterText: counterText,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: base,
      enabledBorder: base,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        borderSide: const BorderSide(color: GridTokens.mint, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        borderSide: const BorderSide(color: GridTokens.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        borderSide: const BorderSide(color: GridTokens.danger, width: 1.5),
      ),
      suffixIcon: suffix,
    );
  }
}
