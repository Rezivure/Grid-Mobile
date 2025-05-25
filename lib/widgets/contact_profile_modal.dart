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

  /// All device keys (fetched from the RoomService)
  late Map<String, Map<String, String>> _allOtherDeviceKeys;

  /// List of sharing windows loaded from the DB
  List<SharingWindow> _sharingWindows = [];

  /// Whether we're currently editing sharing preferences (for showing X buttons)
  bool _isEditingPreferences = false;
  
  /// Whether the device keys section is expanded
  bool _isDeviceKeysExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceKeys();
  }

  Future<void> _loadDeviceKeys() async {
    try {
      // Get device keys directly from RoomService
      final keyData = widget.roomService.getUserDeviceKeys(widget.contact.userId);
      setState(() {
        _allOtherDeviceKeys = keyData;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading device keys: $e');
      setState(() {
        _allOtherDeviceKeys = {};
        _isLoading = false;
      });
    }

    await _loadSharingPreferences();
  }

  Future<void> _loadSharingPreferences() async {
    try {
      final prefs = await widget.sharingPreferencesRepo.getSharingPreferences(widget.contact.userId, 'contact');
      setState(() {
        _alwaysShare = prefs?.activeSharing ?? false;
        _sharingWindows = prefs?.shareWindows ?? [];
      });
    } catch (e) {
      setState(() {
        _alwaysShare = false;
        _sharingWindows = [];
      });
    }
  }

  Future<void> _saveToDatabase() async {
    final preferences = SharingPreferences(
      targetId: widget.contact.userId,
      targetType: 'contact',
      activeSharing: _alwaysShare,
      shareWindows: _sharingWindows,
    );
    await widget.sharingPreferencesRepo.setSharingPreferences(preferences);
  }

  String? getRoomId(String userId) {
    // This method is simplified since we're not using it for device keys anymore
    return null;
  }

  Widget _buildModernKeyRow(String keyType, String keyValue) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  keyType,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: keyValue));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$keyType key copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: Icon(
                  Icons.copy,
                  size: 18,
                  color: colorScheme.primary,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primary.withOpacity(0.1),
                  minimumSize: const Size(32, 32),
                  padding: const EdgeInsets.all(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Text(
              keyValue,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: colorScheme.onSurface.withOpacity(0.8),
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDeviceKeysList() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Use the device keys directly from the API
    final allDeviceKeys = _allOtherDeviceKeys;

    if (allDeviceKeys.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              Icons.security,
              size: 48,
              color: colorScheme.onSurface.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No Security Keys Available',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Security keys will appear here once the contact is verified',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Compare these keys with those shown in your contact's settings to verify their identity.",
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...allDeviceKeys.entries.map((entry) {
          final deviceId = entry.key;
          final keys = entry.value;
          final isCurrentDevice = false; // Since we don't track current device anymore

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCurrentDevice 
                    ? colorScheme.primary.withOpacity(0.3)
                    : colorScheme.outline.withOpacity(0.1),
                width: isCurrentDevice ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ExpansionTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCurrentDevice 
                          ? colorScheme.primary.withOpacity(0.1)
                          : colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isCurrentDevice ? Icons.smartphone : Icons.devices,
                      color: isCurrentDevice 
                          ? colorScheme.primary
                          : colorScheme.onSurface.withOpacity(0.6),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          deviceId,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.6),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildModernKeyRow('Curve25519', keys['curve25519'] ?? 'N/A'),
                      _buildModernKeyRow('Ed25519', keys['ed25519'] ?? 'N/A'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userLocalpart = widget.contact.userId.split(':')[0].replaceFirst('@', '');

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.background,
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

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modern Header
                  _buildModernHeader(theme, colorScheme, userLocalpart),
                  
                  const SizedBox(height: 32),

                  // Always Share Section
                  _buildAlwaysShareSection(theme, colorScheme),

                  const SizedBox(height: 24),

                  // Sharing Windows Section
                  if (!_alwaysShare) ...[
                    _buildSharingWindowsSection(theme, colorScheme),
                    const SizedBox(height: 24),
                  ],

                  // Security Section
                  _buildSecuritySection(theme, colorScheme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHeader(ThemeData theme, ColorScheme colorScheme, String userLocalpart) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Enhanced avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.primary.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: colorScheme.primary.withOpacity(0.1),
              child: RandomAvatar(
                userLocalpart,
                height: 64,
                width: 64,
              ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Contact info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.contact.displayName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatUserId(widget.contact.userId),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          
          // Copy button
          IconButton(
            onPressed: () {
              final textToCopy = formatUserId(widget.contact.userId).contains(":")
                  ? widget.contact.userId.substring(1)
                  : userLocalpart;
              
              Clipboard.setData(ClipboardData(text: textToCopy));
              setState(() => _copied = true);
              
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() => _copied = false);
                }
              });
            },
            icon: Icon(
              _copied ? Icons.check : Icons.copy,
              color: colorScheme.primary,
            ),
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.primary.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlwaysShareSection(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.share_location,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Always Share Location',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Share your location with this contact 24/7',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
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
                activeColor: colorScheme.primary,
              ),
            ],
          ),
          if (_alwaysShare) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                  width: 1,
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
                      'Turn off to set custom sharing windows',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.primary,
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

  Widget _buildSharingWindowsSection(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.schedule,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Sharing Windows',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (_sharingWindows.isNotEmpty)
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
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          if (_sharingWindows.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 32,
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No sharing windows set',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add windows to share your location at specific times',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _openAddSharingPreferenceModal,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Window'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._sharingWindows.map((window) {
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: window.isActive
                                ? colorScheme.primary.withOpacity(0.1)
                                : colorScheme.surfaceVariant.withOpacity(0.3),
                            border: Border.all(
                              color: window.isActive
                                  ? colorScheme.primary
                                  : colorScheme.outline.withOpacity(0.3),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            window.label,
                            style: TextStyle(
                              color: window.isActive
                                  ? colorScheme.primary
                                  : colorScheme.onSurface.withOpacity(0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.red,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                }).toList(),
                
                GestureDetector(
                  onTap: _openAddSharingPreferenceModal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary.withOpacity(0.1),
                          colorScheme.primary.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: colorScheme.primary.withOpacity(0.3),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.add,
                            size: 14,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Add Window',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isDeviceKeysExpanded = !_isDeviceKeysExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.security,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Security Details',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Verify your contact\'s identity',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isDeviceKeysExpanded ? Icons.expand_less : Icons.expand_more,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ],
              ),
            ),
          ),
          
          
          if (_isDeviceKeysExpanded) ...[
            const SizedBox(height: 16),
            if (_isLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                    color: colorScheme.primary,
                  ),
                ),
              )
            else
              _buildModernDeviceKeysList(),
          ],
        ],
      ),
    );
  }
}