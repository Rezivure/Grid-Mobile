import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:grid_frontend/components/modals/notice_continue_modal.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';

class FriendRequestModal extends StatefulWidget {
  final RoomService roomService;
  final String userId;
  final String displayName;
  final String roomId;
  final Future<void> Function() onResponse; // Callback for refreshing

  FriendRequestModal({
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isCustomServer = isCustomHomeserver();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,  // Start taller
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle indicator
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header with close button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.person_add,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Friend Request',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),  // Reduced top padding
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Profile section
                    _buildProfileCard(theme, colorScheme, isCustomServer),
                    
                    const SizedBox(height: 16),  // Reduced from 24
                    
                    // Action buttons
                    if (_isProcessing)
                      _buildLoadingState(theme, colorScheme)
                    else
                      _buildActionButtons(theme, colorScheme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(ThemeData theme, ColorScheme colorScheme, bool isCustomServer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),  // Reduced from 24
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: RandomAvatar(
              widget.userId.split(":").first.replaceFirst('@', ''),
              height: 70.0,  // Reduced from 80
              width: 70.0,   // Reduced from 80
            ),
          ),
          
          const SizedBox(height: 12),  // Reduced from 16
          
          // Display name
          Text(
            '@${widget.displayName}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          
          // User ID for custom servers
          if (isCustomServer) ...[
            const SizedBox(height: 4),
            Text(
              widget.userId,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          
          const SizedBox(height: 12),  // Reduced from 16
          
          // Description
          Container(
            padding: const EdgeInsets.all(12),  // Reduced from 16
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: colorScheme.primary,
                  size: 18,  // Reduced from 20
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Wants to connect with you. You will begin sharing locations once you accept.',
                    style: theme.textTheme.bodySmall?.copyWith(  // Changed from bodyMedium
                      color: colorScheme.onSurface,
                      height: 1.3,  // Reduced from 1.4
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

  Widget _buildLoadingState(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          CircularProgressIndicator(
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Processing request...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        // Location sharing checkbox
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.1),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _startSharingOnJoin,
                  onChanged: (value) {
                    setState(() {
                      _startSharingOnJoin = value ?? true;
                    });
                  },
                  activeColor: colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start sharing on join',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _startSharingOnJoin 
                        ? 'Share your location immediately when connecting'
                        : 'Location sharing will be disabled for this contact',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Accept button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _acceptRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Accept Request',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Decline button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: _declineRequest,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.close, size: 20, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Decline',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
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
      await Provider.of<SyncManager>(context, listen: false).acceptInviteAndSync(widget.roomId);

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
          targetId: widget.userId,  // Use the user ID, not room ID
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
            content: Text("Friend request accepted."),
            backgroundColor: Theme.of(context).colorScheme.primary,
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
        Provider.of<SyncManager>(context, listen: false).removeInvite(widget.roomId);
        Navigator.of(context).pop(); // Close the modal
        await widget.onResponse(); // Refresh the list
        
        String errorMessage = "This invitation has expired or is no longer valid.";
        if (e.toString().toLowerCase().contains('forbidden')) {
          errorMessage = "This invitation has already been accepted or declined.";
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Expanded(child: Text(errorMessage)),
              ],
            ),
            backgroundColor: Colors.orange,
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
        Provider.of<SyncManager>(context, listen: false).removeInvite(widget.roomId);
        
        // Give time for the bloc state to update and UI to reflect changes
        await Future.delayed(const Duration(milliseconds: 300));
        
        Navigator.of(context).pop();
        await widget.onResponse();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Friend request declined."),
            backgroundColor: Theme.of(context).colorScheme.primary,
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
            backgroundColor: Theme.of(context).colorScheme.error,
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