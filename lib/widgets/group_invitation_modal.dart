import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/components/modals/notice_continue_modal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_status_pill.dart';

class GroupInvitationModal extends StatefulWidget {
  final RoomService roomService;
  final String groupName;
  final String roomId;
  final String inviter;
  final int expiration;
  final Future<void> Function() refreshCallback;

  GroupInvitationModal({
    required this.groupName,
    required this.roomId,
    required this.inviter,
    required this.expiration,
    required this.refreshCallback,
    required this.roomService,
  });

  @override
  _GroupInvitationModalState createState() => _GroupInvitationModalState();
}

String calculateExpiryTime(int expiration) {
  DateTime now = DateTime.now();
  int timeNowSeconds = now.millisecondsSinceEpoch ~/ 1000;
  int timeDifferenceInSeconds = expiration - timeNowSeconds;

  if (expiration == -1 || timeDifferenceInSeconds <= 0) {
    return "Permanent";
  } else {
    int minutes = (timeDifferenceInSeconds / 60).round();
    int hours = (minutes / 60).round();
    int days = (hours / 24).round();

    if (days > 0) {
      return "$days day${days > 1 ? 's' : ''}";
    } else if (hours > 0) {
      return "$hours hour${hours > 1 ? 's' : ''}";
    } else if (minutes > 0) {
      return "$minutes minute${minutes > 1 ? 's' : ''}";
    } else {
      return "a few seconds";
    }
  }
}

class _GroupInvitationModalState extends State<GroupInvitationModal> {
  bool _isProcessing = false;
  bool _startSharingOnJoin = true; // Default to checked
  late String expiry;

  @override
  void initState() {
    super.initState();
    expiry = calculateExpiryTime(widget.expiration);
  }

  /// Returns the handle (e.g. "jordan.t") from a Matrix ID like "@jordan.t:grid.cloud".
  String get _inviterHandle {
    final raw = widget.inviter.split(':').first;
    return raw.replaceFirst('@', '');
  }

  /// Returns the homeserver (e.g. "grid.cloud") from a Matrix ID.
  String get _inviterHomeserver {
    final parts = widget.inviter.split(':');
    return parts.length > 1 ? parts.sublist(1).join(':') : 'grid.cloud';
  }

  /// Synthesize avatar seeds for the stacked-avatar cluster at the top.
  /// We don't have the full member list here — the inviter is the only known
  /// real participant, so the rest are deterministic stand-ins keyed off the
  /// room id and group name. The visual goal is the cluster pattern from
  /// `21-invites-active.png` (GroupInviteCard).
  List<String> get _avatarSeeds {
    final inviter = _inviterHandle;
    final room = widget.roomId;
    final name = widget.groupName;
    return [
      inviter,
      '$inviter.$room',
      '$name.$room',
      'group.$room',
    ];
  }

  bool get _isTrip => expiry != 'Permanent';

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.gridColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(GridTokens.r2Xl)),
          border: Border(
            top: BorderSide(color: context.gridColors.hairlineStrong, width: 1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grab handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.gridColors.text4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Close button row (no header title — content is the moment)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  const Spacer(),
                  _CloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Stacked avatars cluster
                    const SizedBox(height: 12),
                    Center(child: _buildStackedAvatars()),

                    const SizedBox(height: 18),

                    // Optional TRIP pill (amber) when the group has an expiration
                    if (_isTrip) ...[
                      Center(
                        child: GridStatusPill(
                          kind: GridStatusKind.trip,
                          label: 'TRIP · $expiry',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Group name
                    Text(
                      widget.groupName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: context.gridColors.text,
                        letterSpacing: -0.01,
                        height: 1.15,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Mono subtitle: "@inviter · grid.cloud"
                    Center(
                      child: GridMono(
                        '@$_inviterHandle · $_inviterHomeserver',
                        size: 12,
                        uppercase: false,
                        letterSpacing: 0.02,
                        color: context.gridColors.text3,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Mint-faint "Wants to add you to this group" card
                    _buildMintFaintCard(),

                    const SizedBox(height: 12),

                    // Action buttons / loading state
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
    );
  }

  Widget _buildStackedAvatars() {
    const double avatarSize = 56;
    const double overlap = 18; // negative-margin overlap
    final seeds = _avatarSeeds;

    return SizedBox(
      height: avatarSize + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < seeds.length; i++)
            Positioned(
              left: i * (avatarSize - overlap),
              child: GridAvatar(
                name: seeds[i],
                size: avatarSize,
                padding: 2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMintFaintCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: context.gridColors.mintFaint,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
      ),
      child: Row(
        children: [
          Icon(Icons.group_rounded, size: 18, color: context.gridColors.mint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '@$_inviterHandle wants to add you to this group.',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.gridColors.text,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: context.gridColors.mint,
            ),
          ),
          const SizedBox(height: 14),
          GridMono(
            'PROCESSING INVITATION',
            size: 11,
            letterSpacing: 0.12,
            color: context.gridColors.text3,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // "Start sharing with the group" toggle row — surface card + mint check tile
        _ShareToggleRow(
          value: _startSharingOnJoin,
          onChanged: (v) => setState(() => _startSharingOnJoin = v),
        ),
        const SizedBox(height: 16),

        // Primary: Join group
        GridButton(
          label: 'Join group',
          icon: Icons.check_rounded,
          onPressed: _acceptGroupInvitation,
        ),
        const SizedBox(height: 10),

        // Danger ghost: Decline
        GridButton(
          label: 'Decline',
          style: GridButtonStyle.danger,
          onPressed: _declineGroupInvitation,
        ),
      ],
    );
  }

  Future<void> _acceptGroupInvitation() async {
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final syncManager = Provider.of<SyncManager>(context, listen: false);
      final groupsBloc = context.read<GroupsBloc>();
      final mapBloc = context.read<MapBloc>();

      // Accept the invitation through SyncManager to ensure proper syncing
      await syncManager.acceptInviteAndSync(widget.roomId);

      // Handle location sharing based on checkbox
      if (_startSharingOnJoin) {
        // Send immediate location update
        final locationManager = context.read<LocationManager>();
        await locationManager.grabLocationAndPing();

        // Send location specifically to this room
        await widget.roomService.updateSingleRoom(widget.roomId);
      } else {
        // Disable location sharing for this group
        final sharingPrefs = context.read<SharingPreferencesRepository>();
        final preferences = SharingPreferences(
          targetId: widget.roomId,
          targetType: 'group',
          activeSharing: false,
          shareWindows: null,
        );
        await sharingPrefs.setSharingPreferences(preferences);
      }

      // Close the modal immediately after successful join
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show success message
      if (mounted) {
        InAppNotifier.instance.show(
          title: 'Group invitation accepted',
          variant: InAppNotificationVariant.success,
          duration: const Duration(seconds: 2),
        );
      }

      // Now do the cleanup and updates
      await Future.delayed(const Duration(milliseconds: 500));

      // Remove invite and update UI
      syncManager.removeInvite(widget.roomId);

      // Multiple updates to ensure UI synchronization
      groupsBloc.add(RefreshGroups());
      groupsBloc.add(LoadGroups());
      mapBloc.add(MapLoadUserLocations());

      // Staggered updates to ensure everything syncs properly
      Future.delayed(const Duration(milliseconds: 750), () {
        if (mounted) {
          groupsBloc.add(RefreshGroups());
          groupsBloc.add(LoadGroups());
          groupsBloc.add(LoadGroupMembers(widget.roomId));
        }
      });

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          groupsBloc.add(RefreshGroups());
          groupsBloc.add(LoadGroups());
          mapBloc.add(MapLoadUserLocations());
        }
      });

      // Call the refresh callback if it exists
      try {
        await widget.refreshCallback();
      } catch (callbackError) {
        print('Error in refresh callback: $callbackError');
        // Don't throw, as the join was successful
      }
    } catch (e) {
      print('Error in _acceptGroupInvitation: $e');
      print('Error type: ${e.runtimeType}');

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        // Only show the invalid invite modal for specific errors
        if (e.toString().contains('403') || e.toString().contains('not_in_room') || e.toString().contains('Invalid')) {
          Navigator.of(context).pop();
          Provider.of<SyncManager>(context, listen: false).removeInvite(widget.roomId);

          await showDialog(
            context: context,
            builder: (context) => NoticeContinueModal(
              message: "The invite is no longer valid. It may have been removed.",
              onContinue: () {},
            ),
          );
        } else {
          InAppNotifier.instance.show(
            title: 'Error accepting invitation',
            message: e.toString(),
            variant: InAppNotificationVariant.error,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _declineGroupInvitation() async {
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Decline the invitation using RoomService
      await widget.roomService.declineInvitation(widget.roomId);

      // Remove the invitation from SyncManager BEFORE closing modal
      if (mounted) {
        Provider.of<SyncManager>(context, listen: false).removeInvite(widget.roomId);

        // Give time for the bloc state to update and UI to reflect changes
        await Future.delayed(const Duration(milliseconds: 300));

        Navigator.of(context).pop(); // Close the modal
        await widget.refreshCallback(); // Trigger the callback to refresh

        InAppNotifier.instance.show(
          title: 'Group invitation declined',
          variant: InAppNotificationVariant.info,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        InAppNotifier.instance.show(
          title: 'Failed to decline group invitation',
          message: '$e',
          variant: InAppNotificationVariant.error,
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

/// Small surface2 tap target with hairline border + close glyph. Avoids
/// pulling in a new shared primitive while keeping the close affordance
/// consistent with the redesign chrome.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.gridColors.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: context.gridColors.hairline, width: 1),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.close_rounded, size: 18, color: context.gridColors.text2),
        ),
      ),
    );
  }
}

/// "Start sharing with the group" toggle row — surface2 card with mint check
/// tile on the left, label + helper copy on the right. Tap anywhere on the
/// row to toggle, matching the friend-request modal pattern.
class _ShareToggleRow extends StatelessWidget {
  const _ShareToggleRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.gridColors.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rLg),
            border: Border.all(color: context.gridColors.hairline, width: 1),
          ),
          child: Row(
            children: [
              // Mint check tile
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: value ? context.gridColors.mint : context.gridColors.surface3,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: value ? context.gridColors.mint : context.gridColors.hairlineStrong,
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: value
                    ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF04201A))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start sharing with the group',
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.gridColors.text,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value
                          ? 'You can adjust this anytime.'
                          : 'You can turn it on later in group settings.',
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: context.gridColors.text3,
                        height: 1.3,
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
}
