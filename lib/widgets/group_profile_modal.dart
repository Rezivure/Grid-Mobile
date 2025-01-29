import 'package:flutter/material.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/models/grid_user.dart';
import 'package:grid_frontend/models/sharing_window.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/widgets/add_sharing_preferences_modal.dart';
import 'package:grid_frontend/widgets/triangle_avatars.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/utilities/utils.dart';

import '../blocs/groups/groups_state.dart';

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

class _GroupProfileModalState extends State<GroupProfileModal> {
  bool _copied = false;
  bool _alwaysShare = false;
  bool _isEditingPreferences = false;
  List<SharingWindow> _sharingWindows = [];
  bool _membersExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadSharingPreferences();
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


    final now = DateTime
        .now()
        .millisecondsSinceEpoch ~/ 1000;

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

  void _openAddSharingPreferenceModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) {
        return AddSharingPreferenceModal(
          onSave: (label, selectedDays, isAllDay, startTime, endTime) async {
            final newWindow = SharingWindow(
              label: label,
              days: _daysToIntList(selectedDays),
              isAllDay: isAllDay,
              // Convert TimeOfDay to "HH:mm" if not all-day
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

  Widget _buildMembersList(List<GridUser> members) {
    final theme = Theme.of(context);

    return Column(
      children: members.map((member) {
        final powerLevel = widget.roomService.getUserPowerLevel(
          widget.room.roomId,
          member.userId,
        );
        var adminStatus = powerLevel == 100;
        var membershipStatus = adminStatus ?'Admin' : '';

        return ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            child: RandomAvatar(
              member.userId.split(':')[0].replaceFirst('@', ''),
              height: 40,
              width: 40,
            ),
          ),
          title: Text(member.displayName ?? formatUserId(member.userId)),
          subtitle: Text(formatUserId(member.userId)),
          trailing: Text(
            membershipStatus,
            style: TextStyle(
              color: theme.colorScheme.onBackground.withOpacity(0.7),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Material(
        color: colorScheme.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group Header
                      Row(
                        children: [
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: TriangleAvatars(userIds: widget.room.members),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _getGroupName(),
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onBackground,
                                        ),
                                      ),
                                      Text(
                                        _getExpirationText(),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colorScheme.onBackground.withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Always Share toggle
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 16.0),
                                child: Text(
                                  'Always Share',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _alwaysShare,
                                onChanged: (value) async {
                                  setState(() {
                                    _alwaysShare = value;
                                  });
                                  await _saveToDatabase();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Subtitle text
                      if (_alwaysShare)
                        const Padding(
                          padding: EdgeInsets.only(left: 16.0, top: 4.0),
                          child: Text(
                            'Turn off "Always Share" to set custom sharing preferences.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey, // Subtle color for subtitle
                            ),
                          ),
                        ),
                      // Sharing Windows Section
                      if (!_alwaysShare) ...[
                        Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                'Sharing Windows',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onBackground,
                                ),
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isEditingPreferences = !_isEditingPreferences;
                                });
                              },
                              child: Text(
                                _isEditingPreferences ? 'Save' : 'Edit',
                                style: TextStyle(color: colorScheme.primary),
                              ),
                            ),
                          ],
                        ),
                        // Sharing windows display
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: [
                              ..._sharingWindows.map((window) => _buildSharingWindow(window)),
                              if (!_isEditingPreferences)
                                _buildAddNewButton(),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Members Section
                      ExpansionTile(
                        title: const Text('Members'),
                        children: [
                          BlocBuilder<GroupsBloc, GroupsState>(
                            builder: (context, state) {
                              if (state is GroupsLoaded && state.selectedRoomMembers != null) {
                                return _buildMembersList(state.selectedRoomMembers!);
                              }
                              return const Center(child: CircularProgressIndicator());
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  onPressed: widget.onMemberAdded,
                  child: const Text('Add Member'),
                ),
              ),
              // Close button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.onSurface,
                    foregroundColor: colorScheme.surface,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSharingWindow(SharingWindow window) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
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
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            decoration: BoxDecoration(
              color: window.isActive
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                  : Theme.of(context).colorScheme.background,
              border: Border.all(
                color: window.isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(window.label),
          ),
        ),
        if (_isEditingPreferences)
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: () async {
                setState(() {
                  _sharingWindows.remove(window);
                });
                await _saveToDatabase();
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent,
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAddNewButton() {
    return InkWell(
      onTap: _openAddSharingPreferenceModal,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              size: 16,
              color: Theme.of(context).colorScheme.onBackground,
            ),
            const SizedBox(width: 4),
            Text(
              'Add New...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onBackground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}