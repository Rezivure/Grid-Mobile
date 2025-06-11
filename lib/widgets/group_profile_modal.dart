import 'package:flutter/material.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/models/grid_user.dart';
import 'package:grid_frontend/models/sharing_window.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/services/profile_picture_service.dart';
import 'package:grid_frontend/services/profile_announcement_service.dart';
import 'package:grid_frontend/services/others_profile_service.dart';
import 'package:grid_frontend/services/message_processor.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/widgets/add_sharing_preferences_modal.dart';
import 'package:grid_frontend/widgets/triangle_avatars.dart';
import 'package:grid_frontend/widgets/cached_group_avatar.dart';
import 'package:grid_frontend/widgets/cached_profile_avatar.dart';
import 'package:grid_frontend/widgets/profile_picture_modal.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/providers/profile_picture_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../blocs/groups/groups_state.dart';
import '../blocs/groups/groups_event.dart';

class GroupProfileModal extends StatefulWidget {
  final Room room;
  final RoomService roomService;
  final SharingPreferencesRepository sharingPreferencesRepo;
  final VoidCallback onMemberAdded;

  const GroupProfileModal({
    Key? key,
    required this.room,
    required this.roomService,
    required this.sharingPreferencesRepo,
    required this.onMemberAdded,
  }) : super(key: key);

  @override
  _GroupProfileModalState createState() => _GroupProfileModalState();
}

class _GroupProfileModalState extends State<GroupProfileModal> with TickerProviderStateMixin {
  bool _copied = false;
  bool _alwaysShare = false;
  bool _isEditingPreferences = false;
  List<SharingWindow> _sharingWindows = [];
  bool _membersExpanded = false;
  bool _isUploadingAvatar = false;
  
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  
  final ProfilePictureService _profilePictureService = ProfilePictureService();
  late ProfileAnnouncementService _profileAnnouncementService;

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
    _profileAnnouncementService = ProfileAnnouncementService(
      client: widget.roomService.client,
      profilePictureService: _profilePictureService,
    );
    _loadSharingPreferences();
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  /// Load sharing windows & the 'alwaysShare' flag from the DB
  Future<void> _loadSharingPreferences() async {
    final prefs = await widget.sharingPreferencesRepo.getSharingPreferences(
      widget.room.roomId,
      'group',
    );

    if (prefs != null) {
      setState(() {
        _sharingWindows = prefs.shareWindows ?? [];
        _alwaysShare = prefs.activeSharing;
      });
    }
  }

  String _getExpirationText() {
    final expirationTimestamp = extractExpirationTimestamp(widget.room.name);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (expirationTimestamp == 0) {
      return "Permanent Group";
    }
    final remainingSeconds = expirationTimestamp - now;

    if (remainingSeconds <= 0) {
      return 'Expired';
    }

    final duration = Duration(seconds: remainingSeconds);
    if (duration.inDays > 0) {
      return 'Expires in: ${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return 'Expires in: ${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return 'Expires in: ${duration.inMinutes}m';
    }
  }

  /// Save the current sharing windows & 'alwaysShare' to the DB
  Future<void> _saveToDatabase() async {
    final newPrefs = SharingPreferences(
      targetId: widget.room.roomId,
      targetType: 'group',
      activeSharing: _alwaysShare,
      shareWindows: _sharingWindows,
    );
    await widget.sharingPreferencesRepo.setSharingPreferences(newPrefs);
  }
  
  /// Check if current user has permission to change group avatar
  Future<bool> _canChangeAvatar() async {
    try {
      final room = widget.roomService.client.getRoomById(widget.room.roomId);
      if (room == null) return false;
      
      final myUserId = widget.roomService.client.userID;
      if (myUserId == null) return false;
      
      final powerLevel = room.getPowerLevelByUserId(myUserId);
      return powerLevel >= 50; // Admin or moderator
    } catch (e) {
      print('Error checking avatar permissions: $e');
      return false;
    }
  }
  
  /// Show profile picture modal for group avatar
  void _showGroupAvatarModal() async {
    // Check if custom homeserver
    if (isCustomHomeserver(widget.roomService.getMyHomeserver())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Group avatars are only available on default server'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    
    // Check permissions
    final canChange = await _canChangeAvatar();
    if (!canChange) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Only group admins can change the avatar'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => ProfilePictureModal(
        onImageSelected: _handleGroupAvatarSelected,
      ),
    );
  }
  
  /// Handle group avatar selection
  Future<void> _handleGroupAvatarSelected(File imageFile) async {
    setState(() {
      _isUploadingAvatar = true;
    });
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('loginToken');
      
      if (jwtToken == null) {
        throw Exception('No authentication token found');
      }
      
      // Upload the avatar using profile picture service
      final metadata = await _profilePictureService.uploadProfilePicture(
        imageFile, 
        jwtToken
      );
      
      // Create group avatar announcement content
      final content = {
        'msgtype': 'grid.group.avatar.announce',
        'body': 'Group avatar updated',
        'avatar': {
          'url': metadata['url'],
          'key': metadata['key'],
          'iv': metadata['iv'],
          'version': metadata['version'] ?? '1.0',
          'updated_at': metadata['uploadedAt'],
        }
      };
      
      // Send announcement to the group
      final room = widget.roomService.client.getRoomById(widget.room.roomId);
      if (room != null) {
        await room.sendEvent(content);
        print('GroupProfileModal: Sent group avatar announcement to room ${widget.room.roomId}');
        print('GroupProfileModal: Avatar metadata: $metadata');
      }
      
      // Also save the group avatar locally for the uploader
      await _saveGroupAvatarLocally(metadata);
      
      // Download and cache the image for the uploader
      await _downloadAndCacheGroupAvatar(metadata);
      
      print('Successfully set group avatar for room ${widget.room.roomId}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Group avatar updated successfully'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Failed to set group avatar: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update group avatar'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isUploadingAvatar = false;
      });
    }
  }

  /// Save group avatar metadata locally for the uploader
  Future<void> _saveGroupAvatarLocally(Map<String, dynamic> metadata) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing group avatars metadata
      final allMetadataStr = prefs.getString('group_avatars_metadata');
      final allMetadata = allMetadataStr != null 
          ? json.decode(allMetadataStr) as Map<String, dynamic>
          : <String, dynamic>{};
      
      // Add this group's avatar metadata
      allMetadata[widget.room.roomId] = {
        'url': metadata['url'],
        'key': metadata['key'],
        'iv': metadata['iv'],
        'version': metadata['version'] ?? '1.0',
        'updated_at': metadata['uploadedAt'],
        'cached_at': DateTime.now().toIso8601String(),
      };
      
      // Save back to preferences
      await prefs.setString('group_avatars_metadata', json.encode(allMetadata));
      
      print('GroupProfileModal: Saved group avatar metadata locally');
    } catch (e) {
      print('Error saving group avatar metadata: $e');
    }
  }
  
  /// Download and cache the group avatar for immediate display
  Future<void> _downloadAndCacheGroupAvatar(Map<String, dynamic> metadata) async {
    try {
      final url = metadata['url'] as String;
      final key = metadata['key'] as String;
      final iv = metadata['iv'] as String;
      
      // Download the avatar
      final avatarBytes = await _profilePictureService.downloadProfilePicture(url, key, iv);
      
      if (avatarBytes != null) {
        // Process the group avatar announcement to cache it using the singleton instance
        await MessageProcessor.othersProfileService.processGroupAvatarAnnouncement(widget.room.roomId, {
          'url': url,
          'key': key,
          'iv': iv,
          'version': metadata['version'] ?? '1.0',
          'updated_at': metadata['uploadedAt'],
        });
        
        // Small delay to ensure cache is written
        await Future.delayed(Duration(milliseconds: 100));
        
        // Notify UI to update
        if (mounted) {
          Provider.of<ProfilePictureProvider>(context, listen: false)
              .notifyProfileUpdated(widget.room.roomId);
          
          // Trigger groups refresh
          context.read<GroupsBloc>().add(RefreshGroups());
        }
        
        print('GroupProfileModal: Downloaded and cached group avatar for immediate display');
      }
    } catch (e) {
      print('Error downloading and caching group avatar: $e');
    }
  }
  
  void _openAddSharingPreferenceModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: AddSharingPreferenceModal(
          onSave: (label, selectedDays, isAllDay, startTime, endTime) async {
            final newWindow = SharingWindow(
              label: label,
              days: _daysToIntList(selectedDays),
              isAllDay: isAllDay,
              startTime: (isAllDay || startTime == null)
                  ? null
                  : '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
              endTime: (isAllDay || endTime == null)
                  ? null
                  : '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
              isActive: true,
            );

            setState(() {
              _sharingWindows.add(newWindow);
            });
            await _saveToDatabase();
          },
        ),
        );
      },
    );
  }

  List<int> _daysToIntList(List<bool> selectedDays) {
    final days = <int>[];
    for (int i = 0; i < selectedDays.length; i++) {
      if (selectedDays[i]) days.add(i);
    }
    return days;
  }

  String _getGroupName() {
    if (widget.room.name == null) return 'Unnamed Group';
    final parts = widget.room.name!.split(':');
    if (parts.length >= 5) {
      return parts[3];
    }
    return widget.room.name!;
  }

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

  Widget _buildModernHeader() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return _buildModernCard(
      child: Row(
        children: [
          // Modern avatar with subtle glow
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: CachedGroupAvatar(
                    roomId: widget.room.roomId,
                    memberIds: widget.room.members,
                    radius: 36,
                    groupName: _getGroupName(),
                  ),
                ),
              ),
              if (!isCustomHomeserver(widget.roomService.getMyHomeserver()))
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: FutureBuilder<bool>(
                    future: _canChangeAvatar(),
                    builder: (context, snapshot) {
                      if (snapshot.data == true) {
                        return GestureDetector(
                          onTap: _isUploadingAvatar ? null : _showGroupAvatarModal,
                          child: Container(
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: colorScheme.outline.withOpacity(0.2),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: _isUploadingAvatar
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.primary,
                                    ),
                                  )
                                : Icon(
                                    Icons.camera_alt,
                                    size: 14,
                                    color: colorScheme.primary,
                                  ),
                          ),
                        );
                      }
                      return SizedBox.shrink();
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getGroupName(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getExpirationText(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.room.members.length} members',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharingPreferencesCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return _buildModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.share_location,
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
                      'Location Sharing',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      _alwaysShare ? 'Always sharing' : 'Custom schedule',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.9,
                child: Switch.adaptive(
                  value: _alwaysShare,
                  onChanged: (value) async {
                    setState(() {
                      _alwaysShare = value;
                    });
                    await _saveToDatabase();
                  },
                  activeColor: colorScheme.primary,
                ),
              ),
            ],
          ),
          
          if (_alwaysShare) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: colorScheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your location is shared with this group at all times',
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
          
          if (!_alwaysShare) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sharing Windows',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isEditingPreferences = !_isEditingPreferences;
                    });
                  },
                  icon: Icon(
                    _isEditingPreferences ? Icons.check : Icons.edit,
                    size: 16,
                  ),
                  label: Text(_isEditingPreferences ? 'Done' : 'Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12.0,
              runSpacing: 12.0,
              children: [
                ..._sharingWindows.map((window) => _buildModernSharingWindow(window)),
                if (!_isEditingPreferences) _buildModernAddButton(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembersCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return _buildModernCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.group,
                    color: colorScheme.secondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Group Members',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _membersExpanded = !_membersExpanded;
                    });
                  },
                  icon: AnimatedRotation(
                    turns: _membersExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: _membersExpanded ? null : 0,
            child: _membersExpanded
                ? BlocBuilder<GroupsBloc, GroupsState>(
                    builder: (context, state) {
                      if (state is GroupsLoaded && state.selectedRoomMembers != null) {
                        return _buildModernMembersList(state.selectedRoomMembers!);
                      }
                      return Container(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildModernMembersList(List<GridUser> members) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        const Divider(height: 1),
        ...members.asMap().entries.map((entry) {
          final index = entry.key;
          final member = entry.value;
          
          final powerLevel = widget.roomService.getUserPowerLevel(
            widget.room.roomId,
            member.userId,
          );
          final isAdmin = powerLevel == 100;
          final isLastItem = index == members.length - 1;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: isLastItem
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: colorScheme.outline.withOpacity(0.1),
                      ),
                    ),
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isAdmin 
                          ? colorScheme.primary.withOpacity(0.3)
                          : colorScheme.outline.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: CachedProfileAvatar(
                    userId: member.userId,
                    radius: 22,
                    displayName: member.displayName,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.displayName ?? formatUserId(member.userId),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatUserId(member.userId),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isAdmin)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      'Admin',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildModernSharingWindow(SharingWindow window) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () async {
            if (!_isEditingPreferences) {
              final index = _sharingWindows.indexOf(window);
              final updatedWindow = SharingWindow(
                label: window.label,
                days: window.days,
                isAllDay: window.isAllDay,
                startTime: window.startTime,
                endTime: window.endTime,
                isActive: !window.isActive,
              );

              setState(() {
                _sharingWindows[index] = updatedWindow;
              });
              await _saveToDatabase();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: window.isActive
                  ? colorScheme.primary
                  : colorScheme.surface,
              border: Border.all(
                color: window.isActive
                    ? colorScheme.primary
                    : colorScheme.outline.withOpacity(0.3),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: window.isActive
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              window.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: window.isActive
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (_isEditingPreferences)
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: () async {
                setState(() {
                  _sharingWindows.remove(window);
                });
                await _saveToDatabase();
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.surface,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: colorScheme.onError,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildModernAddButton() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return GestureDetector(
      onTap: _openAddSharingPreferenceModal,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(
            color: colorScheme.primary.withOpacity(0.3),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Add Window',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernActionButtons() {
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
            child: ElevatedButton(
              onPressed: widget.onMemberAdded,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_add, size: 20),
                  const SizedBox(width: 8),
                  const Text('Add Member'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
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
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.background,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
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
            
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _buildModernHeader(),
                    _buildSharingPreferencesCard(),
                    _buildMembersCard(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            
            _buildModernActionButtons(),
          ],
        ),
      ),
    );
  }
}