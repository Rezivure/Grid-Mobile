import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';

class FriendRequestModal extends StatefulWidget {
  final RoomService roomService;
  final String userId;
  final String displayName;
  final String roomId;
  final Future<void> Function() onResponse; // Callback for refreshing

  const FriendRequestModal({
    super.key,
    required this.userId,
    required this.displayName,
    required this.roomId,
    required this.onResponse,
    required this.roomService,
  });

  @override
  _FriendRequestModalState createState() => _FriendRequestModalState();
}

class _FriendRequestModalState extends State<FriendRequestModal> {
  bool _isProcessing = false;
  bool _startSharingOnJoin = true; // Default to checked

  bool isCustomHomeserver() {
    final homeserver = widget.roomService.getMyHomeserver();
    return utils.isCustomHomeserver(homeserver);
  }

  String get _homeserverLabel {
    final raw = widget.roomService.getMyHomeserver();
    return raw
        .replaceFirst('https://', '')
        .replaceFirst('http://', '')
        .replaceAll('/', '');
  }

  String get _handle {
    // displayName already comes through as a handle in most paths; strip any
    // leading @ so we can format it consistently as `@handle · homeserver`.
    final clean = widget.displayName.replaceFirst(RegExp(r'^@'), '');
    return clean;
  }

  String get _firstName {
    final clean = widget.displayName.replaceFirst(RegExp(r'^@'), '').trim();
    if (clean.isEmpty) return 'them';
    final parts = clean.split(RegExp(r'[\s._-]+'));
    final first = parts.first;
    if (first.isEmpty) return clean;
    return first[0].toUpperCase() + first.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final bool isCustomServer = isCustomHomeserver();

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(GridTokens.r2Xl),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                color: GridTokens.surface.withOpacity(0.96),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(GridTokens.r2Xl),
                ),
                border: const Border(
                  top: BorderSide(color: GridTokens.hairlineStrong, width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Grab handle (36×4).
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: GridTokens.text4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          _buildIdentity(isCustomServer),
                          const SizedBox(height: 22),
                          _buildIntroCard(),
                          const SizedBox(height: 14),
                          _buildSharingCheckbox(),
                          const SizedBox(height: 22),
                          if (_isProcessing)
                            _buildLoadingState()
                          else
                            _buildActionButtons(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Identity (avatar with mint pin badge + name + mono handle) ──────
  Widget _buildIdentity(bool isCustomServer) {
    final handleLine = isCustomServer
        ? '@$_handle · $_homeserverLabel'
        : '@$_handle · grid.cloud';

    return Column(
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: GridAvatar(
                  name: widget.userId.split(':').first.replaceFirst('@', ''),
                  size: 80,
                ),
              ),
              // Mint location-pin badge in the lower-right with a 3pt bg border.
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: GridTokens.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: GridTokens.surface, width: 3),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: GridTokens.mint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on,
                      size: 16,
                      color: Color(0xFF04201A),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _firstName == 'them' ? '@$_handle' : _firstName,
          textAlign: TextAlign.center,
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.02,
            color: GridTokens.text,
          ),
        ),
        const SizedBox(height: 4),
        GridMono(
          handleLine,
          uppercase: false,
          size: 12,
          letterSpacing: 0.04,
          color: GridTokens.text3,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Mint-faint "wants to share location with you" card ──────────────
  Widget _buildIntroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: GridTokens.mintFaint,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: GridTokens.mintSoft, width: 1),
      ),
      child: Text(
        'Wants to share location with you.',
        textAlign: TextAlign.center,
        style: GoogleFonts.getFont(
          'Geist',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.01,
          color: GridTokens.text,
        ),
      ),
    );
  }

  // ── Surface card with mint check tile + "Start sharing with X" ──────
  Widget _buildSharingCheckbox() {
    final on = _startSharingOnJoin;
    final firstName = _firstName == 'them' ? _handle : _firstName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        onTap: () => setState(() => _startSharingOnJoin = !on),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: GridTokens.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.hairline, width: 1),
          ),
          child: Row(
            children: [
              // Mint check tile.
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: on ? GridTokens.mint : GridTokens.surface3,
                  borderRadius: BorderRadius.circular(GridTokens.rSm),
                  border: Border.all(
                    color: on ? GridTokens.mint : GridTokens.hairlineStrong,
                    width: 1,
                  ),
                ),
                child: on
                    ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Color(0xFF04201A),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start sharing with $firstName',
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: GridTokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      on
                          ? 'You can adjust this anytime.'
                          : 'Location sharing will stay off for this contact.',
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        color: GridTokens.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(GridTokens.mint),
            ),
          ),
          const SizedBox(height: 14),
          GridMono(
            'PROCESSING REQUEST',
            color: GridTokens.text3,
            size: 11,
            letterSpacing: 0.12,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        GridButton(
          label: 'Accept request',
          icon: Icons.check_rounded,
          onPressed: _acceptRequest,
        ),
        const SizedBox(height: 10),
        GridButton(
          label: 'Decline',
          style: GridButtonStyle.danger,
          onPressed: _declineRequest,
        ),
      ],
    );
  }

  Future<void> _acceptRequest() async {
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Accept invitation and sync via SyncManager
      await Provider.of<SyncManager>(context, listen: false)
          .acceptInviteAndSync(widget.roomId);

      print("Refreshing contacts via bloc...");

      if (mounted) {
        // Dispatch RefreshContacts to update ContactsBloc
        context.read<ContactsBloc>().add(RefreshContacts());
      }

      // Handle location sharing based on checkbox
      if (_startSharingOnJoin) {
        // Send immediate location update
        final locationManager = context.read<LocationManager>();
        await locationManager.grabLocationAndPing();

        // Send location specifically to this room
        await widget.roomService.updateSingleRoom(widget.roomId);
      } else {
        // Disable location sharing for this contact
        final sharingPrefs = context.read<SharingPreferencesRepository>();
        final preferences = SharingPreferences(
          targetId: widget.userId, // Use the user ID, not room ID
          targetType: 'user',
          activeSharing: false,
          shareWindows: null,
        );
        await sharingPrefs.setSharingPreferences(preferences);
      }

      if (mounted) {
        Navigator.of(context).pop(); // Close the modal
        await widget.onResponse(); // Execute callback to refresh any parent components

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Friend request accepted."),
            backgroundColor: GridTokens.mint,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Remove the invite from the list if it's expired or invalid
        Provider.of<SyncManager>(context, listen: false)
            .removeInvite(widget.roomId);
        Navigator.of(context).pop(); // Close the modal
        await widget.onResponse(); // Refresh the list

        String errorMessage =
            "This invitation has expired or is no longer valid.";
        if (e.toString().toLowerCase().contains('forbidden')) {
          errorMessage =
              "This invitation has already been accepted or declined.";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(errorMessage)),
              ],
            ),
            backgroundColor: GridTokens.amber,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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

  Future<void> _declineRequest() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await widget.roomService.declineInvitation(widget.roomId);

      // Remove invite from the list BEFORE closing modal
      if (mounted) {
        Provider.of<SyncManager>(context, listen: false)
            .removeInvite(widget.roomId);

        // Give time for the bloc state to update and UI to reflect changes
        await Future.delayed(const Duration(milliseconds: 300));

        Navigator.of(context).pop();
        await widget.onResponse();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Friend request declined."),
            backgroundColor: GridTokens.mint,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error declining the request: $e"),
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
}
