import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/widgets/add_sharing_preferences_modal.dart';

import '../models/sharing_window.dart';
import '../models/sharing_preferences.dart';
import '../repositories/sharing_preferences_repository.dart';

class ContactProfileModal extends StatefulWidget {
  final ContactDisplay contact;
  final RoomService roomService;
  final SharingPreferencesRepository sharingPreferencesRepo;

  const ContactProfileModal({
    Key? key,
    required this.contact,
    required this.roomService,
    required this.sharingPreferencesRepo,
  }) : super(key: key);

  @override
  _ContactProfileModalState createState() => _ContactProfileModalState();
}

class _ContactProfileModalState extends State<ContactProfileModal> {
  bool _copied = false;
  bool _isLoading = true;
  bool _alwaysShare = false;

  /// All device keys except current (fetched from the RoomService)
  late Map<String, Map<String, String>> _allOtherDeviceKeys;

  /// The most recent/current device key
  late Map<String, String>? _latestDeviceKey;
  late String? _latestDeviceId;

  /// List of sharing windows loaded from the DB
  List<SharingWindow> _sharingWindows = [];

  /// Whether we're currently editing sharing preferences (for showing X buttons)
  bool _isEditingPreferences = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceKeys();
    _loadSharingPreferences();
  }

  /// Load device keys from the RoomService
  Future<void> _loadDeviceKeys() async {
    setState(() => _isLoading = true);

    _allOtherDeviceKeys = widget.roomService.getUserDeviceKeys(widget.contact.userId);

    // No need to handle latest device separately anymore since we're showing all keys together
    _latestDeviceId = null;
    _latestDeviceKey = null;

    setState(() => _isLoading = false);
  }
  /// Load sharing windows & the 'alwaysShare' flag from the DB
  Future<void> _loadSharingPreferences() async {
    final prefs = await widget.sharingPreferencesRepo.getSharingPreferences(
      widget.contact.userId,
      'user',
    );

    if (prefs != null) {
      setState(() {
        _sharingWindows = prefs.shareWindows ?? [];
        _alwaysShare = prefs.activeSharing;
      });
    }
  }

  /// Save the current sharing windows & 'alwaysShare' to the DB
  Future<void> _saveToDatabase() async {
    final newPrefs = SharingPreferences(
      targetId: widget.contact.userId,
      targetType: 'user',
      activeSharing: _alwaysShare,
      shareWindows: _sharingWindows,
    );
    await widget.sharingPreferencesRepo.setSharingPreferences(newPrefs);
  }

  /// Helper to build rows for each device key
  Widget _buildKeyRow(String keyType, String keyValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          keyType,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onBackground,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                keyValue,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Monospace',
                  color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.copy,
                size: 20,
                color: Theme.of(context).colorScheme.onBackground,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: keyValue));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Key copied to clipboard')),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDeviceKeysList() {
    // Combine current device with other devices
    final allDeviceKeys = Map<String, Map<String, String>>.from(_allOtherDeviceKeys);
    if (_latestDeviceKey != null && _latestDeviceId != null) {
      allDeviceKeys[_latestDeviceId!] = _latestDeviceKey!;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [

        const SizedBox(height: 8),
        Text(
          "You'll see keys from all of your contact's login sessions here. Some may be from older or inactive sessions, but they're kept for security history. Compare these with the keys shown in your contact's settings page to verify their identity.",
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        ...allDeviceKeys.entries.map((entry) {
          final deviceId = entry.key;
          final keys = entry.value;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ExpansionTile(
              title: Text(
                'Device: $deviceId',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildKeyRow('Curve25519', keys['curve25519'] ?? 'N/A'),
                      const SizedBox(height: 8),
                      _buildKeyRow('Ed25519', keys['ed25519'] ?? 'N/A'),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  /// Open the AddSharingPreferenceModal to create a new SharingWindow
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
              startTime: startTime != null ? startTime.format(context) : null,
              endTime: endTime != null ? endTime.format(context) : null,
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

  /// Convert a List<bool> to a List<int> (assuming 0=Monday, etc.)
  List<int> _daysToIntList(List<bool> selectedDays) {
    final days = <int>[];
    for (int i = 0; i < selectedDays.length; i++) {
      if (selectedDays[i]) days.add(i);
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userLocalpart = widget.contact.userId.split(':')[0].replaceFirst('@', '');

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
              // Main content area
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile header
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: colorScheme.primary.withOpacity(0.1),
                            child: RandomAvatar(
                              userLocalpart,
                              height: 60,
                              width: 60,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.contact.displayName,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onBackground,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        formatUserId(widget.contact.userId),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colorScheme.onBackground.withOpacity(0.7),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.copy,
                                    color: colorScheme.onBackground,
                                  ),
                                  onPressed: () {

                                    if (formatUserId(widget.contact.userId).contains(":")) {
                                      Clipboard.setData(
                                          ClipboardData(
                                            text: widget.contact.userId.substring(1),
                                          ),
                                      );
                                    } else {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: userLocalpart,
                                        ),
                                      );
                                    }

                                    setState(() => _copied = true);
                                    Future.delayed(const Duration(seconds: 2), () {
                                      if (mounted) {
                                        setState(() => _copied = false);
                                      }
                                    });
                                  },
                                ),
                                if (_copied)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Text(
                                      'Copied',
                                      style: TextStyle(
                                        color: colorScheme.onBackground,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // "Always Share" toggle
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header and Switch
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
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Sharing Preferences Section (shown only if not always sharing)
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
                            Padding(
                              padding: const EdgeInsets.only(right: 16.0),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _isEditingPreferences = !_isEditingPreferences;
                                  });
                                },
                                child: Text(
                                  _isEditingPreferences ? 'Save' : 'Edit',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Actual sharing windows display
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: [
                              ..._sharingWindows.map((window) {
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // The chip itself
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
                                              ? colorScheme.primary.withOpacity(0.15)
                                              : colorScheme.background,
                                          border: Border.all(
                                            color: window.isActive
                                                ? colorScheme.primary
                                                : colorScheme.outline,
                                            width: 1,
                                          ),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          window.label,
                                          style: TextStyle(
                                            color: colorScheme.onBackground,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Show 'X' button if in edit mode
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
                              }).toList(),

                              // Add New button (only if not editing)
                              if (!_isEditingPreferences)
                                InkWell(
                                  onTap: _openAddSharingPreferenceModal,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0, vertical: 8.0),
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      border: Border.all(
                                        color: colorScheme.outline,
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.add,
                                          size: 16,
                                          color: colorScheme.onBackground,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Add New...',
                                          style: TextStyle(
                                            color: colorScheme.onBackground,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Device Keys Section
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        ExpansionTile(
                          title: Text(
                            'Security Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onBackground,
                            ),
                          ),
                          children: [
                            if (_latestDeviceKey == null && _allOtherDeviceKeys.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: Text('No device keys available'),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 4.0,
                                ),
                                child: _buildDeviceKeysList(),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              // Close button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.onSurface,
                      foregroundColor: colorScheme.surface,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Close'),
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
