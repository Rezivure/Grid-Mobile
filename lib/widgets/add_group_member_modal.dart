import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../repositories/user_repository.dart';
import '../styles/tokens.dart';
import 'grid/grid_avatar.dart';
import 'grid/grid_button.dart';
import 'grid/grid_mono.dart';

class AddGroupMemberModal extends StatefulWidget {
  final String roomId;
  final String? groupName;
  final UserService userService;
  final RoomService roomService;
  final UserRepository userRepository;
  final VoidCallback? onInviteSent;

  AddGroupMemberModal({
    required this.roomId,
    this.groupName,
    required this.userService,
    required this.roomService,
    required this.userRepository,
    required this.onInviteSent,
  });

  @override
  _AddGroupMemberModalState createState() => _AddGroupMemberModalState();
}

class _AddGroupMemberModalState extends State<AddGroupMemberModal>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  bool _isProcessing = false;

  // QR code scanning variables
  bool _isScanning = false;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _qrController;
  bool hasScanned = false;
  String? _matrixUserId = "";
  String? _contactError;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

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
      // Re-render so the preview avatar tracks the handle.
      if (mounted) setState(() {});
    });

    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _controller.dispose();
    _qrController?.dispose();
    super.dispose();
  }

  bool isCustomHomeserver() {
    final homeserver = this.widget.roomService.getMyHomeserver();
    return utils.isCustomHomeserver(homeserver);
  }

  void _shareGroupInvite() async {
    try {
      final groupName = widget.groupName ?? 'our group';
      final message = 'Join me on Grid! Download it at https://get.grid.lat and share your username to get invited to the $groupName group!';

      await Share.share(
        message,
        subject: 'Grid Group Invite',
      );
    } catch (e) {
      print('Error sharing group invite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to share invite: ${e.toString()}'),
            backgroundColor: GridTokens.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GridTokens.rMd),
            ),
          ),
        );
      }
    }
  }

  void _addMember() async {
    // No hard limit on group members
    // const int MAX_GROUP_MEMBERS = 15;

    var username = _controller.text.trim().toLowerCase();
    bool isCustomServer = isCustomHomeserver();

    if (username.isEmpty) {
      if (mounted) {
        setState(() {
          _contactError = 'Please enter a valid username';
        });
      }
      return;
    }

    if (isCustomServer) {
      // For custom homeservers, expect full matrix ID without @ prefix
      if (!username.contains(':')) {
        setState(() {
          _contactError = 'Please enter full Matrix ID (e.g., user:domain.com)';
        });
        return;
      }
      username = '@$username';
    } else {
      // For default homeserver, just add local part
      final homeserver = this.widget.roomService.getMyHomeserver().replaceFirst('https://', '');
      username = '@$username:$homeserver';
    }

    if (mounted) {
      setState(() {
        _isProcessing = true;
        _contactError = null;
      });
    }

    try {
      // check if inviting self
      final isSelf = (await widget.roomService.getMyUserId() == username);
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
            _contactError =
                'You do not have permission to invite members to this group.';
            _isProcessing = false;
          });
        }
        return;
      }

      // No member limit check - groups can have unlimited members
      // Previously limited to 15, now removed per request

      // Verify user exists
      if (!await widget.userService.userExists(username)) {
        if (mounted) {
          setState(() {
            _contactError = 'The user $username does not exist.';
            _isProcessing = false;
          });
        }
        return;
      }

      // Check if already in group
      if (await widget.roomService.isUserInRoom(widget.roomId, username)) {
        if (mounted) {
          setState(() {
            _contactError = 'The user $username is already in the group.';
            _isProcessing = false;
          });
        }
        return;
      }

      // Send the matrix invite
      await widget.roomService.client.inviteUser(widget.roomId, username);

      // Let GroupsBloc handle the state updates
      context.read<GroupsBloc>().handleNewMemberInvited(widget.roomId, username);

      if (widget.onInviteSent != null) {
        widget.onInviteSent!();
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invite sent to @${utils.localpart(username)}'),
            backgroundColor: GridTokens.surface2,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GridTokens.rMd),
              side: const BorderSide(color: GridTokens.hairlineStrong),
            ),
          ),
        );
      }

      _matrixUserId = null;
    } catch (e) {
      print('Error adding member: $e');
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
    bool isCustomServ = isCustomHomeserver();
    controller.scannedDataStream.listen((scanData) async {
      if (!hasScanned) {
        String scannedUserId = scanData.code ?? '';
        print('Scanned QR Code: $scannedUserId');

        if (scannedUserId.isNotEmpty) {
          hasScanned = true;
          controller.pauseCamera(); // Pause the camera to avoid rescanning
          setState(() {
            _isScanning = false;
            // For custom homeservers, preserve the full matrix ID (without @)
            // For default homeserver, extract just the localpart
            if (isCustomServ && scannedUserId.contains(':')) {
              _controller.text = scannedUserId.replaceFirst('@', '');
            } else {
              _controller.text = scannedUserId.split(":").first.replaceFirst('@', '');
            }
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

  // ── Build ────────────────────────────────────────────────────────────────

  String get _handle => _controller.text.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        decoration: const BoxDecoration(
          color: GridTokens.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(GridTokens.r2Xl),
            topRight: Radius.circular(GridTokens.r2Xl),
          ),
          border: Border(
            top: BorderSide(color: GridTokens.hairlineStrong, width: 1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Sheet grabber
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: GridTokens.hairlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    if (_isScanning)
                      _buildQRScanner()
                    else ...[
                      _buildPreview(),
                      const SizedBox(height: 20),
                      const GridMono('Username',
                          color: GridTokens.text3,
                          size: 10,
                          letterSpacing: 0.12),
                      const SizedBox(height: 10),
                      _buildHandleInput(),
                      const SizedBox(height: 10),
                      _buildHelperLine(),
                      if (_contactError != null) ...[
                        const SizedBox(height: 14),
                        _buildErrorCard(),
                      ],
                      const SizedBox(height: 24),
                      _buildSecondaryRow(),
                    ],
                  ],
                ),
              ),
            ),
            if (!_isScanning) _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GridMono('Add member',
            color: GridTokens.text3, size: 10, letterSpacing: 0.14),
        const SizedBox(height: 6),
        Text(
          widget.groupName == null
              ? 'Invite to group.'
              : 'Invite to ${widget.groupName}.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.025 * 26,
            color: GridTokens.text,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Location sharing begins once they accept.',
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: GridTokens.text2,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ── Member preview card ─────────────────────────────────────────────────

  Widget _buildPreview() {
    final hasHandle = _handle.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: GridTokens.surface2,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: GridTokens.hairline, width: 1),
      ),
      child: Row(
        children: [
          GridAvatar(
            name: hasHandle ? _handle : '·',
            size: 44,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasHandle ? '@$_handle' : 'New member',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(
                    'Geist Mono',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: GridTokens.text,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                GridMono(
                  hasHandle ? 'Pending invite' : 'Type a handle to preview',
                  color: GridTokens.text3,
                  size: 10,
                  letterSpacing: 0.12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Handle input (mint border, surface2 well, @ prefix) ─────────────────

  Widget _buildHandleInput() {
    final hasContent = _handle.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: GridTokens.surface2,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(
          color: _contactError != null ? GridTokens.danger : GridTokens.mint,
          width: 1.5,
        ),
        boxShadow: _contactError != null
            ? null
            : [
                BoxShadow(
                  color: GridTokens.mint.withOpacity(0.18),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: Row(
        children: [
          Text(
            '@',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: GridTokens.text3,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              cursorColor: GridTokens.mint,
              cursorWidth: 2,
              style: GoogleFonts.getFont(
                'Geist Mono',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: GridTokens.text,
                height: 1.0,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: hasContent
                    ? null
                    : (isCustomHomeserver()
                        ? 'john:homeserver.io'
                        : 'username'),
                hintStyle: GoogleFonts.getFont(
                  'Geist Mono',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: GridTokens.text3,
                ),
              ),
              onSubmitted: (_) {
                if (!_isProcessing) _addMember();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelperLine() {
    final body = GoogleFonts.getFont(
      'Geist',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: GridTokens.text3,
    );
    final mono = GoogleFonts.getFont(
      'Geist Mono',
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: GridTokens.text3,
    );
    if (isCustomHomeserver()) {
      return Text(
        'Enter the full Matrix ID (user:domain).',
        style: body,
      );
    }
    return Text(
      'Enter your friend\'s handle.',
      style: body,
    );
  }

  // ── Inline error card (danger / dangerSoft) ─────────────────────────────

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GridTokens.dangerSoft,
        borderRadius: BorderRadius.circular(GridTokens.rSm),
        border: Border.all(color: GridTokens.danger.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: GridTokens.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _contactError!,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: GridTokens.danger,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Secondary row: scan QR ──────────────────────────────────────────────

  Widget _buildSecondaryRow() {
    return _SecondaryAction(
      icon: Icons.qr_code_scanner_rounded,
      label: 'Scan QR',
      onTap: _scanQRCode,
    );
  }

  // ── QR Scanner panel ────────────────────────────────────────────────────

  Widget _buildQRScanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GridTokens.surface2,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: GridTokens.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _qrController?.pauseCamera();
                    setState(() {
                      _isScanning = false;
                    });
                  },
                  borderRadius: BorderRadius.circular(GridTokens.rMd),
                  child: Ink(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: GridTokens.surface,
                      borderRadius: BorderRadius.circular(GridTokens.rMd),
                      border: Border.all(
                          color: GridTokens.hairlineStrong, width: 1),
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        size: 18, color: GridTokens.text),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Scan QR code',
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: GridTokens.text,
                  letterSpacing: -0.01,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: GridTokens.bg,
              borderRadius: BorderRadius.circular(GridTokens.rMd),
              border: Border.all(color: GridTokens.hairlineStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: QrScannerOverlayShape(
                borderColor: GridTokens.mint,
                borderRadius: 12,
                borderLength: 30,
                borderWidth: 4,
                cutOutSize: 250,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: GridTokens.text3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Point your camera at a user's QR code to add them instantly.",
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: GridTokens.text3,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bottom action bar ───────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: GridTokens.surface,
        border: Border(
          top: BorderSide(color: GridTokens.hairline, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GridButton(
              label: 'Cancel',
              style: GridButtonStyle.secondary,
              onPressed: _isProcessing
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _isProcessing
                ? _buildLoadingButton()
                : GridButton(
                    label: 'Add to group',
                    onPressed: _addMember,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingButton() {
    return Container(
      height: 52,
      width: double.infinity,
      decoration: BoxDecoration(
        color: GridTokens.mint.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF04201A)),
        ),
      ),
    );
  }
}

// ── Tiny private widgets ────────────────────────────────────────────────────

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: GridTokens.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.hairline, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: GridTokens.mint),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: GridTokens.text,
                    letterSpacing: -0.005,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
