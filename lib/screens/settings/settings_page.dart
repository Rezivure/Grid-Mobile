import 'package:flutter/material.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/sync_manager.dart';
import '/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/services/sharing_state_notifier.dart';
import 'package:grid_frontend/services/theme_controller.dart';
import 'package:grid_frontend/services/location/home_geofence_service.dart';
import 'package:grid_frontend/services/location/location_dispatch.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'dart:convert';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grid_frontend/widgets/user_avatar.dart';
import 'package:grid_frontend/widgets/user_avatar_bloc.dart';
import 'package:grid_frontend/services/avatar_announcement_service.dart';
import 'package:grid_frontend/services/avatar_cache_service.dart';
import 'package:grid_frontend/blocs/avatar/avatar_bloc.dart';
import 'package:grid_frontend/blocs/avatar/avatar_event.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';
import 'package:grid_frontend/blocs/invitations/invitations_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_event.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/screens/settings/subscription_screen.dart';
import 'package:grid_frontend/screens/settings/passkey_management_screen.dart';
import 'package:grid_frontend/screens/settings/developer_tools_screen.dart';
import 'package:grid_frontend/screens/settings/encryption_keys_screen.dart';
import 'package:grid_frontend/screens/settings/home_location_picker_screen.dart';
import 'package:grid_frontend/screens/settings/profile_photo_screen.dart';
import 'package:grid_frontend/screens/settings/appearance_settings_screen.dart';
import 'package:grid_frontend/screens/settings/sharing_mode_screen.dart';
import 'dart:io' show Platform;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../styles/tokens.dart';
import '../../styles/grid_colors.dart';
import '../../widgets/grid/grid_avatar.dart';
import '../../widgets/grid/grid_button.dart';
import '../../widgets/grid/grid_mono.dart';
import '../../widgets/grid/grid_segmented.dart';



class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Static cache for avatar to persist across widget recreations
  static final Map<String, Uint8List> _avatarCache = {};
  static final Map<String, String> _avatarUriCache = {};

  String? deviceID;
  String? identityKey;
  String _selectedProxy = 'None';
  TextEditingController _customProxyController = TextEditingController();
  String _appVersion = '';
  String _buildNumber = '';
  bool _incognitoMode = false;
  bool _batterySaver = false;
  SharingMode _sharingMode = SharingMode.balanced;
  bool _autoPauseAtHome = false;
  bool _homeLocationSet = false;
  String? _userID;
  String? _username;
  String? _localpart;
  String? _displayName;
  bool _isEditingDisplayName = false;
  Uint8List? _avatarBytes;
  bool _isLoadingAvatar = false;
  String? _cachedAvatarUri; // Track the URI to avoid re-downloading
  bool _hasLoadedAvatar = false; // Track if we've attempted to load avatar
  int _avatarUpdateCounter = 0; // Force UserAvatar widget rebuild

  // Hidden dev-tools easter egg: 5 taps on the footer within a 3s rolling
  // window opens the Developer Tools screen.
  int _devTapCount = 0;
  DateTime? _lastDevTapAt;

  void _onFooterTapped() {
    final now = DateTime.now();
    if (_lastDevTapAt != null &&
        now.difference(_lastDevTapAt!) <= const Duration(seconds: 3)) {
      _devTapCount += 1;
    } else {
      _devTapCount = 1;
    }
    _lastDevTapAt = now;
    if (_devTapCount >= 5) {
      _devTapCount = 0;
      _lastDevTapAt = null;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DeveloperToolsScreen(),
        ),
      );
    }
  }


  @override
  void initState() {
    super.initState();
    _getDeviceAndIdentityKey();
    _loadUser();
    _loadIncognitoState();
    _loadBatterySaverState();
    _loadAutoPauseAtHomeState();
    _loadCachedAvatar();
    _loadAppVersion();
  }
  
  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = 'v${packageInfo.version}';
      _buildNumber = packageInfo.buildNumber;
    });
  }

  bool isCustomHomeserver() {
    final roomService = Provider.of<RoomService>(context, listen: false);
    final homeserver = roomService.getMyHomeserver();
    return utils.isCustomHomeserver(homeserver);
  }

  Future<void> _loadUser() async {
    try {
      final client = Provider.of<Client>(context, listen: false);
      final prefs = await SharedPreferences.getInstance();
      bool isCustomServer = isCustomHomeserver();
      setState(() {
        _userID = client.userID?.replaceAll('@', '');
        _localpart = _userID?.split(':')[0].replaceAll('@', '') ?? 'Unknown User';
        _username =  isCustomServer ? _userID : _userID?.split(':')[0].replaceAll('@', '') ?? 'Unknown User';
        _displayName = prefs.getString('displayName') ?? _username;
      });
    } catch (e) {
      print('Error loading user: $e');
      setState(() {
        _username = 'Unknown User';
        _displayName = 'Unknown User';
      });
    }
  }

  Future<void> _loadIncognitoState() async {
    final sharingState = context.read<SharingStateNotifier>();
    if (!mounted) return;
    setState(() {
      _incognitoMode = sharingState.userIncognito;
    });
  }

  Future<void> _loadBatterySaverState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _batterySaver = prefs.getBool('battery_saver') ?? false;
      _sharingMode =
          SharingModePref.fromPrefValue(prefs.getString('sharing_mode'));
    });
  }

  Future<void> _loadAutoPauseAtHomeState() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('home_location');
    setState(() {
      _autoPauseAtHome =
          prefs.getBool('auto_pause_at_home_enabled') ?? false;
      _homeLocationSet = saved != null && saved.trim().isNotEmpty;
    });
  }

  void _showExpandedAvatar(BuildContext context) {
    final client = Provider.of<Client>(context, listen: false);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(20),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: Hero(
                  tag: 'settings_avatar_${client.userID}',
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.width * 0.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    child: ClipOval(
                      child: UserAvatarBloc(
                        userId: client.userID ?? '',
                        size: MediaQuery.of(context).size.width * 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Drives the user-facing 'Sharing mode' slider. Persists the choice,
  /// swaps the underlying `libre_location` preset at runtime via
  /// LocationDispatch, and keeps the legacy `battery_saver` pref in sync
  /// for any consumer that still reads it.
  Future<void> _setSharingMode(SharingMode mode) async {
    if (_sharingMode == mode) return;
    setState(() => _sharingMode = mode);
    try {
      await context.read<LocationDispatch>().setMode(mode);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final wantBatterySaver = mode == SharingMode.light;
    if (_batterySaver != wantBatterySaver) {
      await prefs.setBool('battery_saver', wantBatterySaver);
      if (mounted) setState(() => _batterySaver = wantBatterySaver);
      try {
        Provider.of<LocationManager>(context, listen: false)
            .toggleBatterySaverMode(wantBatterySaver);
      } catch (_) {}
    }
  }

  Future<void> _toggleBatterySaver(bool value) async {
    final locationManager = Provider.of<LocationManager>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _batterySaver = value;
    });

    await prefs.setBool('battery_saver', value);

    if (value) {
      // enable incognito
      locationManager.toggleBatterySaverMode(value);
      InAppNotifier.instance.show(
        title: 'Battery Saver Mode enabled',
        variant: InAppNotificationVariant.success,
      );
    } else {
      locationManager.toggleBatterySaverMode(value);
      InAppNotifier.instance.show(
        title: 'Battery Saver Mode disabled',
        variant: InAppNotificationVariant.info,
      );
    }
  }

  Future<void> _toggleIncognitoMode(bool value) async {
    final locationManager = Provider.of<LocationManager>(context, listen: false);
    final sharingState = context.read<SharingStateNotifier>();

    setState(() {
      _incognitoMode = value;
    });

    await sharingState.setUserIncognito(value);

    if (value) {
      locationManager.stopTracking();
      InAppNotifier.instance.show(
        title: 'Sharing paused',
        message: 'Your location is no longer being shared.',
        variant: InAppNotificationVariant.info,
      );
    } else {
      locationManager.startTracking();
      InAppNotifier.instance.show(
        title: 'Sharing resumed',
        message: 'Your location is being shared with trusted contacts.',
        variant: InAppNotificationVariant.success,
      );
    }
  }

  // ── Auto-pause at home ─────────────────────────────────
  //
  // Toggle + home-location prefs are owned here; the actual platform
  // geofence is registered by HomeGeofenceService, which we resync any
  // time any of these prefs change so add/remove happens immediately.
  Future<void> _syncHomeGeofence() async {
    try {
      await context.read<HomeGeofenceService>().syncFromPrefs();
    } catch (_) {
      // Provider may not be mounted in some test/preview surfaces — fine.
    }
  }

  Future<void> _onAutoPauseAtHomeToggled(bool requested) async {
    final prefs = await SharedPreferences.getInstance();

    if (!requested) {
      // Turning off: keep the saved home location, just clear the enabled flag.
      await prefs.setBool('auto_pause_at_home_enabled', false);
      await _syncHomeGeofence();
      if (!mounted) return;
      setState(() => _autoPauseAtHome = false);
      return;
    }

    // Turning on: ensure we have a saved home location first.
    final existing = prefs.getString('home_location');
    if (existing != null && existing.trim().isNotEmpty) {
      await prefs.setBool('auto_pause_at_home_enabled', true);
      await _syncHomeGeofence();
      if (!mounted) return;
      setState(() => _autoPauseAtHome = true);
      return;
    }

    // No home set — prompt the user to pick one on the map.
    final saved = await _promptSetHomeLocation();
    if (!mounted) return;
    if (!saved) {
      // User cancelled — leave the toggle off.
      setState(() => _autoPauseAtHome = false);
      return;
    }

    await prefs.setBool('auto_pause_at_home_enabled', true);
    await _syncHomeGeofence();
    if (!mounted) return;
    setState(() {
      _autoPauseAtHome = true;
      _homeLocationSet = true;
    });
  }

  /// Pushes the home-location picker so the user can re-pick their saved
  /// home spot. Overwrites the `home_location` + `home_radius` preferences.
  Future<void> _changeHomeLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final initialRadius = prefs.getDouble('home_radius') ?? 25;
    final picked = await Navigator.of(context).push<HomeLocationResult>(
      MaterialPageRoute(
        builder: (_) =>
            HomeLocationPickerScreen(initialRadiusMeters: initialRadius),
      ),
    );
    if (picked == null || !mounted) return;

    await prefs.setString(
      'home_location',
      '${picked.latLng.latitude},${picked.latLng.longitude}',
    );
    await prefs.setDouble('home_radius', picked.radiusMeters);
    await _syncHomeGeofence();
    if (!mounted) return;
    setState(() => _homeLocationSet = true);
    InAppNotifier.instance.show(
      title: 'Home location updated',
      variant: InAppNotificationVariant.success,
    );
  }

  /// Clears the saved home location and turns the auto-pause toggle off,
  /// since the feature can't work without a saved location.
  Future<void> _clearHomeLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('home_location');
    await prefs.remove('home_radius');
    await prefs.setBool('auto_pause_at_home_enabled', false);
    await _syncHomeGeofence();
    if (!mounted) return;
    setState(() {
      _homeLocationSet = false;
      _autoPauseAtHome = false;
    });
    InAppNotifier.instance.show(
      title: 'Home location cleared',
      variant: InAppNotificationVariant.info,
    );
  }

  /// Shows the "Set your home location" bottom sheet and, if the user
  /// confirms, pushes the home-location picker. Returns `true` when a home
  /// location was successfully persisted.
  Future<bool> _promptSetHomeLocation() async {
    final shouldPick = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: context.gridColors.surface,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
                border: Border.all(color: context.gridColors.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: context.gridColors.mintFaint,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.gridColors.mintSoft,
                            width: 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.home_outlined,
                          color: context.gridColors.mint,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Set your home location',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.getFont(
                        'Geist',
                        color: context.gridColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pick the spot on the map. We use it locally to '
                      'pause location sharing when your phone is at home.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.getFont(
                        'Geist',
                        color: context.gridColors.text2,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                        letterSpacing: -0.005,
                      ),
                    ),
                    const SizedBox(height: 20),
                    GridButton(
                      label: 'Pick on map',
                      icon: Icons.map_outlined,
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(true),
                    ),
                    const SizedBox(height: 8),
                    GridButton(
                      label: 'Cancel',
                      style: GridButtonStyle.ghost,
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (shouldPick != true || !mounted) return false;

    final picked = await Navigator.of(context).push<HomeLocationResult>(
      MaterialPageRoute(
        builder: (_) => const HomeLocationPickerScreen(),
      ),
    );

    if (picked == null) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'home_location',
      '${picked.latLng.latitude},${picked.latLng.longitude}',
    );
    await prefs.setDouble('home_radius', picked.radiusMeters);
    await _syncHomeGeofence();
    return true;
  }

  Future<void> _getDeviceAndIdentityKey() async {
    final client = Provider.of<Client>(context, listen: false);
    final deviceId = client.deviceID;  // Get device ID
    final identityKey = client.identityKey;  // Get identity key

    setState(() {
      this.deviceID = deviceId ?? 'Device ID not available';
      this.identityKey = identityKey.isNotEmpty ? identityKey : 'Identity Key not available';
    });
  }

  void _showInfoModal(String title, String content) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: BoxDecoration(
              color: colorScheme.background,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Section
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outline.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          title.toLowerCase().contains('device') 
                              ? Icons.device_hub 
                              : Icons.key,
                          color: colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onBackground,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Tap and hold to copy',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onBackground.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.close,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content Section
                Flexible(
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Value:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onBackground.withOpacity(0.7),
                          ),
                        ),
                        SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: SelectableText(
                            content,
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurface,
                              fontFamily: 'monospace',
                              height: 1.4,
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        
                        // Info Section
                        Container(
                          padding: EdgeInsets.all(16),
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
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  title.toLowerCase().contains('device')
                                      ? 'This unique identifier helps verify your device for secure communication.'
                                      : 'This cryptographic key ensures end-to-end encryption for your messages.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.primary,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Actions Section
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: colorScheme.outline.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: TextButton.icon(
                            onPressed: () {
                              // Copy to clipboard functionality would go here
                              Navigator.pop(context);
                              InAppNotifier.instance.show(
                                title: '$title copied to clipboard',
                                variant: InAppNotificationVariant.success,
                              );
                            },
                            icon: Icon(
                              Icons.copy,
                              color: colorScheme.onSurface,
                              size: 18,
                            ),
                            label: Text(
                              'Copy',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary.withOpacity(0.8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withOpacity(0.3),
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Close',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
      },
    );
  }

  Widget _buildAvatar(String username) {
    return ClipOval(
      child: GridAvatarFallback(
        name: _localpart!,
        size: 100,
      ),
    );
  }

  // In SettingsPage, update the _logout method:

  Future<void> _logout() async {
    final client = Provider.of<Client>(context, listen: false);
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final sharedPreferences = await SharedPreferences.getInstance();
    final locationManager = Provider.of<LocationManager>(context, listen: false);
    final syncManager = Provider.of<SyncManager>(context, listen: false);
    final avatarBloc = context.read<AvatarBloc>();
    final contactsBloc = context.read<ContactsBloc>();
    final groupsBloc = context.read<GroupsBloc>();
    final invitationsBloc = context.read<InvitationsBloc>();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _buildSignOutDialog(),
    );

    if (confirmed ?? false) {
      try {
        print("[Logout] Starting logout process...");

        // 1. Stop all active services immediately
        print("[Logout] Stopping location tracking...");
        locationManager.stopTracking();

        // 2. Stop sync manager and clear its state
        print("[Logout] Stopping sync manager...");
        await syncManager.stopSync();
        // Wait a moment to ensure sync has stopped
        await Future.delayed(Duration(milliseconds: 100));

        print("[Logout] Clearing sync state...");
        await syncManager.clearAllState();
        syncManager.clearAllRoomMessages();

        // 3. Clear all BLoC states before touching databases
        print("[Logout] Clearing BLoC states...");
        avatarBloc.add(ClearAvatarCache());
        invitationsBloc.add(ClearInvitations());

        // Clear static caches
        _avatarCache.clear();
        _avatarUriCache.clear();

        // Wait for BLoC events to process
        await Future.delayed(Duration(milliseconds: 100));

        // 4. Logout from Matrix client (this handles its own database)
        print("[Logout] Logging out from Matrix...");
        try {
          if (client.isLogged()) {
            await client.logout();
            print("[Logout] Matrix logout successful");
          } else {
            print("[Logout] Client already logged out");
          }
        } catch (e) {
          print("[Logout] Error during Matrix logout: $e");
        }

        // 5. Clear local app database AFTER Matrix logout
        print("[Logout] Clearing local database...");
        await databaseService.deleteAndReinitialize();
        print("[Logout] Database cleared");

        // 6. Clear shared preferences (but preserve some app settings if needed)
        print("[Logout] Clearing preferences...");
        final preserveKeys = ['app_theme', 'onboarding_complete']; // Add keys you want to preserve
        final keysToRemove = sharedPreferences.getKeys().where((key) => !preserveKeys.contains(key)).toList();
        for (final key in keysToRemove) {
          await sharedPreferences.remove(key);
        }

        print("[Logout] Logout complete, navigating to welcome screen");
        // Navigate to welcome screen
        Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
      } catch (e) {
        InAppNotifier.instance.show(
          title: 'Failed to sign out',
          message: '$e',
          variant: InAppNotificationVariant.error,
        );
      }
    }
  }

  Future<void> _deactivateSMSAccount() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final locationManager = Provider.of<LocationManager>(context, listen: false);
    final client = Provider.of<Client>(context, listen: false);
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final syncManager = Provider.of<SyncManager>(context, listen: false);

    // Confirm deletion with modern styled dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _buildDeleteConfirmationDialog(),
    );

    // If user canceled or chose "No," just return
    if (shouldDelete != true) {
      return;
    }

    // Grab the phone number from shared prefs
    final phoneNumber = sharedPreferences.getString('phone_number');
    if (phoneNumber == null || phoneNumber.isEmpty) {
      InAppNotifier.instance.show(
        title: 'Phone number not found',
        message: 'Is this a beta/test account?',
        variant: InAppNotificationVariant.warning,
      );
      return;
    }

    try {
      // Attempt to request deactivation
      final requestSuccess = await authProvider.requestDeactivateAccount(phoneNumber);
      if (!requestSuccess) {
        InAppNotifier.instance.show(
          title: 'Failed to request account deactivation',
          variant: InAppNotificationVariant.error,
        );
        return;
      }

      // Prompt user for the confirmation code that was just sent
      final codeController = TextEditingController();
      final smsCode = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _buildSMSConfirmationDialog(codeController),
      );

      // If user canceled or code is empty, abort
      if (smsCode == null || smsCode.isEmpty) {
        InAppNotifier.instance.show(
          title: 'Confirmation code was not entered',
          variant: InAppNotificationVariant.warning,
        );
        return;
      }

      // Try confirming account deactivation
      final confirmSuccess = await authProvider.confirmDeactivateAccount(phoneNumber, smsCode);
      if (!confirmSuccess) {
        InAppNotifier.instance.show(
          title: 'Failed to confirm account deactivation',
          message: 'Please try again.',
          variant: InAppNotificationVariant.error,
        );
        return;
      }

      // If successful, stop location tracking, syncing, etc.
      locationManager.stopTracking();
      await syncManager.clearAllState();
      await syncManager.stopSync();

      // Clear your local database
      await databaseService.deleteAndReinitialize();

      // Clear all shared preferences
      await sharedPreferences.clear();

      try {
        if (client.isLogged()) {
          await client.logout();
          print("Logout successful");
        } else {
          print("Client already logged out");
        }
      } catch (e) {
        print("Error during logout: $e");
      }

      // Navigate the user back to the welcome screen
      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);

    } catch (e) {
      print('Error during deactivation request: $e');
      InAppNotifier.instance.show(
        title: 'Failed to start account deactivation',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  Future<void> _editDisplayName() async {
    final TextEditingController controller = TextEditingController(text: _displayName ?? _username);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    String? errorText;
    bool hasError = false;

    bool isValidName(String name) {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) return false;
      if (trimmedName.length < 3 || trimmedName.length > 14) return false;
      
      // Allow letters, numbers, spaces, emojis, and basic punctuation
      // This regex allows Unicode characters (including emojis)
      final invalidChars = RegExp(r'[<>"/\\|?*]'); // Only block truly problematic characters
      return !invalidChars.hasMatch(trimmedName);
    }

    final String? newDisplayName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                decoration: BoxDecoration(
                  color: context.gridColors.surface,
                  borderRadius: BorderRadius.circular(GridTokens.rXl),
                  border: Border.all(color: context.gridColors.hairline),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: context.gridColors.mintFaint,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(GridTokens.rXl),
                          topRight: Radius.circular(GridTokens.rXl),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: context.gridColors.mintSoft,
                              borderRadius:
                                  BorderRadius.circular(GridTokens.rMd),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.edit,
                              color: context.gridColors.mint,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit display name',
                                  style: GoogleFonts.getFont(
                                    'Geist',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.015,
                                    color: context.gridColors.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Choose how others see you',
                                  style: GoogleFonts.getFont(
                                    'Geist',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: context.gridColors.text2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: controller,
                              autofocus: true,
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 15,
                                color: context.gridColors.text,
                              ),
                              cursorColor: context.gridColors.mint,
                              maxLength: 14,
                              decoration: InputDecoration(
                                hintText: 'Enter your display name',
                                hintStyle: GoogleFonts.getFont(
                                  'Geist',
                                  color: context.gridColors.text3,
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: context.gridColors.surface2,
                                prefixIcon: Icon(
                                  Icons.person_outline,
                                  color: context.gridColors.text3,
                                  size: 20,
                                ),
                                counterText:
                                    '${controller.text.trim().length}/14',
                                counterStyle: GoogleFonts.getFont(
                                  'Geist',
                                  fontSize: 11,
                                  color: hasError
                                      ? context.gridColors.danger
                                      : context.gridColors.text3,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(GridTokens.rMd),
                                  borderSide: BorderSide(
                                    color: hasError
                                        ? context.gridColors.danger
                                        : context.gridColors.hairline,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(GridTokens.rMd),
                                  borderSide: BorderSide(
                                    color: hasError
                                        ? context.gridColors.danger
                                        : context.gridColors.hairline,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(GridTokens.rMd),
                                  borderSide: BorderSide(
                                    color: hasError
                                        ? context.gridColors.danger
                                        : context.gridColors.mint,
                                    width: 1.5,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  hasError = !isValidName(value);
                                  if (hasError) {
                                    final trimmed = value.trim();
                                    if (trimmed.isEmpty) {
                                      errorText =
                                          'Display name cannot be empty';
                                    } else if (trimmed.length < 3) {
                                      errorText =
                                          'Must be at least 3 characters';
                                    } else if (trimmed.length > 14) {
                                      errorText =
                                          'Must be 14 characters or less';
                                    } else {
                                      errorText =
                                          'Contains invalid characters';
                                    }
                                  } else {
                                    errorText = null;
                                  }
                                });
                              },
                            ),
                            if (errorText != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                errorText!,
                                style: GoogleFonts.getFont(
                                  'Geist',
                                  fontSize: 12,
                                  color: context.gridColors.danger,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: context.gridColors.surface2,
                                borderRadius:
                                    BorderRadius.circular(GridTokens.rMd),
                                border:
                                    Border.all(color: context.gridColors.hairline),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.visibility_outlined,
                                    color: context.gridColors.text2,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Display names are only visible to your contacts and group members.',
                                      style: GoogleFonts.getFont(
                                        'Geist',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                        color: context.gridColors.text2,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Actions
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: GridButton(
                              label: 'Cancel',
                              style: GridButtonStyle.secondary,
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GridButton(
                              label: 'Save',
                              style: GridButtonStyle.primary,
                              onPressed: hasError
                                  ? null
                                  : () {
                                      if (isValidName(controller.text)) {
                                        Navigator.pop(
                                            context, controller.text.trim());
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (newDisplayName != null && newDisplayName.isNotEmpty && isValidName(newDisplayName)) {
      setState(() {
        _isEditingDisplayName = true; // Show spinner
      });

      try {
        final client = Provider.of<Client>(context, listen: false);
        final id = client.userID ?? '';
        if (id.isNotEmpty) {
          await client.setProfileField(id, 'displayname', {'displayname': newDisplayName});
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('displayName', newDisplayName);
        }

        setState(() {
          _displayName = newDisplayName;
        });

        InAppNotifier.instance.show(
          title: 'Display name updated',
          variant: InAppNotificationVariant.success,
        );
      } catch (e) {
        InAppNotifier.instance.show(
          title: 'Failed to update display name',
          message: '$e',
          variant: InAppNotificationVariant.error,
        );
      } finally {
        setState(() {
          _isEditingDisplayName = false; // Hide spinner
        });
      }
    }
  }

  Future<void> _pickAndUploadAvatar({ImageSource? presetSource}) async {
    final colorScheme = Theme.of(context).colorScheme;
    final ImagePicker picker = ImagePicker();

    // When called from the new ProfilePhotoScreen we already know which
    // source the user picked, so skip the legacy in-method chooser.
    final ImageSource? source = presetSource ?? await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(maxWidth: 360),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.15),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.account_circle,
                      color: colorScheme.primary,
                      size: 32,
                    ),
                  ),
                  SizedBox(height: 16),
                  
                  // Title
                  Text(
                    'Update Profile Photo',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 24),
                  
                  // Options
                  InkWell(
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.camera_alt,
                              color: colorScheme.primary,
                              size: 24,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Take Photo',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Use your camera',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  InkWell(
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.photo_library,
                              color: colorScheme.primary,
                              size: 24,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Choose from Gallery',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Select existing photo',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  
                  // End-to-end encryption notice
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 14,
                          color: colorScheme.primary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'End-to-end encrypted',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  
                  // Cancel button
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      minimumSize: Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
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

    if (source == null) return;

    try {
      // Add small delay for Android to prevent race condition
      if (Platform.isAndroid) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // Pick image
      print('[Avatar] Starting image picker...');
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image == null) {
        print('[Avatar] Image picker cancelled');
        return;
      }
      
      print('[Avatar] Image picked successfully: ${image.path}');

      // Step 2: Apply circular cropping (skip on Android due to v8.0.2 crash)
      String finalImagePath;
      
      if (Platform.isIOS) {
        // iOS - use the cropper as normal
        CroppedFile? croppedFile;
        try {
          croppedFile = await ImageCropper().cropImage(
            sourcePath: image.path,
            uiSettings: [
              IOSUiSettings(
                title: 'Crop Avatar',
                aspectRatioLockEnabled: true,
                resetAspectRatioEnabled: false,
                aspectRatioPickerButtonHidden: true,
                rotateButtonsHidden: false,
                rotateClockwiseButtonHidden: false,
                doneButtonTitle: 'Done',
                cancelButtonTitle: 'Cancel',
                aspectRatioPresets: [CropAspectRatioPreset.square],
                cropStyle: CropStyle.circle,
              ),
            ],
          );
        } catch (e) {
          print('Image cropper error: $e');
          return;
        }
        
        if (croppedFile == null) return;
        finalImagePath = croppedFile.path;
      } else {
        // Android - skip cropping for now due to crash bug
        print('[Avatar] Skipping cropper on Android due to plugin bug');
        finalImagePath = image.path;
      }

      // Step 2: Determine server type
      final client = Provider.of<Client>(context, listen: false);
      final roomService = Provider.of<RoomService>(context, listen: false);
      final homeserver = roomService.getMyHomeserver();
      final isCustomServer = utils.isCustomHomeserver(homeserver);

      // Log for debugging
      print('Avatar upload - Homeserver: $homeserver, IsCustom: $isCustomServer');

      if (isCustomServer) {
        // Step 6: Custom homeserver - Upload to Matrix media store
        await _uploadAvatarToMatrix(finalImagePath);
      } else {
        // Step 3: Default homeserver - Encrypt and upload to R2
        await _uploadAvatarToR2(finalImagePath);
      }
    } catch (e) {
      InAppNotifier.instance.show(
        title: 'Failed to process image',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  Future<void> _uploadAvatarToR2(String imagePath) async {
    final colorScheme = Theme.of(context).colorScheme;
    final secureStorage = FlutterSecureStorage();
    
    try {
      // Show subtle loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black12,
        builder: (context) => Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                      strokeWidth: 3,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Uploading',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Read image file
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();

      // Generate encryption key and IV
      final key = encrypt.Key.fromSecureRandom(32); // 256-bit key
      final iv = encrypt.IV.fromSecureRandom(16); // 128-bit IV
      
      // Encrypt the image
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encryptBytes(imageBytes, iv: iv);

      // Get JWT token
      final prefs = await SharedPreferences.getInstance();
      final jwt = prefs.getString('loginToken');
      
      if (jwt == null) {
        throw Exception('No authentication token found');
      }

      // Get middleware URL (GAUTH_URL)
      final middlewareUrl = dotenv.env['GAUTH_URL'];
      
      // Create multipart request to middleware
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$middlewareUrl/upload-profile-pic'),
      );
      
      // Add JWT token
      request.headers['Authorization'] = 'Bearer $jwt';
      
      // Add encrypted file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          encrypted.bytes,
          filename: 'avatar.enc',
          contentType: http_parser.MediaType('application', 'octet-stream'),
        ),
      );

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // Close loading dialog
      Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final filename = responseData['filename'];
        
        // Construct CDN URL using the filename
        final cdnBaseUrl = dotenv.env['PROFILE_PIC_CDN_URL'] ?? 'https://profile-store.mygrid.app';;
        final cdnUrl = '$cdnBaseUrl/$filename';

        // Store encryption metadata in secure storage
        final client = Provider.of<Client>(context, listen: false);
        final userId = client.userID ?? '';
        
        final avatarData = {
          'uri': cdnUrl,
          'key': key.base64,
          'iv': iv.base64,
          'filename': filename,
        };
        
        await secureStorage.write(
          key: 'avatar_$userId',
          value: json.encode(avatarData),
        );

        // Also store in Shar edPreferences for quick access
        await prefs.setString('avatar_uri', cdnUrl);
        await prefs.setBool('avatar_is_matrix', false);

        InAppNotifier.instance.show(
          title: 'Avatar updated',
          variant: InAppNotificationVariant.success,
        );

        // Step 4: Clear cache and reload the avatar to display it
        _avatarBytes = null;
        _cachedAvatarUri = null;
        _hasLoadedAvatar = false; // Reset flag to allow reload
        
        // Clear static cache for this user
        _avatarCache.remove(userId);
        _avatarUriCache.remove(userId);
        
        // Notify AvatarBloc about the update
        final avatarBloc = context.read<AvatarBloc>();
        avatarBloc.add(AvatarUpdateReceived(
          userId: userId,
          avatarUrl: cdnUrl,
          encryptionKey: key.base64,
          encryptionIv: iv.base64,
          isMatrixUrl: false,
        ));
        
        // Force rebuild to show the new avatar
        setState(() {});
        
        // Step 5: Broadcast avatar announcement to all rooms
        print('[Avatar Upload] Broadcasting avatar announcement to all rooms');
        final avatarService = AvatarAnnouncementService(client);
        await avatarService.broadcastProfPicToAllRooms();
      } else {
        throw Exception('Upload failed: ${response.body}');
      }
    } catch (e) {
      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      InAppNotifier.instance.show(
        title: 'Failed to upload avatar',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  Future<void> _uploadAvatarToMatrix(String imagePath) async {
    final colorScheme = Theme.of(context).colorScheme;
    final secureStorage = FlutterSecureStorage();
    
    try {
      // Show subtle loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black12,
        builder: (context) => Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                      strokeWidth: 3,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Uploading',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Get Matrix client
      final client = Provider.of<Client>(context, listen: false);
      
      // Read image file
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      
      // Generate encryption key and IV (same as R2)
      final key = encrypt.Key.fromSecureRandom(32); // 256-bit key
      final iv = encrypt.IV.fromSecureRandom(16); // 128-bit IV
      
      // Encrypt the image
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encryptBytes(imageBytes, iv: iv);
      
      // Upload encrypted file to Matrix media store
      print('[Matrix Avatar] Starting upload of encrypted file to Matrix media store');
      final uploadResp = await client.uploadContent(
        encrypted.bytes,
        filename: 'avatar.enc',
        contentType: 'application/octet-stream',
      );
      print('[Matrix Avatar] Upload response: $uploadResp');

      // Close loading dialog
      Navigator.of(context).pop();

      if (uploadResp != null) {
        // Optionally set the avatar URL in Matrix profile (encrypted version)
        // This is optional - you might not want to set it since it's encrypted
        // print('[Matrix Avatar] Setting avatar URL in Matrix profile');
        // await client.setAvatarUrl(
        //   client.userID!,
        //   uploadResp,
        // );
        // print('[Matrix Avatar] Avatar URL set successfully');

        // Store the mxc URL and encryption keys in secure storage
        final userId = client.userID ?? '';
        print('[Matrix Avatar] Storing encrypted avatar data for user: $userId');
        final avatarData = {
          'uri': uploadResp.toString(),
          'key': key.base64,
          'iv': iv.base64,
          'isMatrix': true, // Flag to indicate this is a Matrix URL
        };
        
        await secureStorage.write(
          key: 'avatar_$userId',
          value: json.encode(avatarData),
        );
        print('[Matrix Avatar] Stored in secure storage');

        // Also store in SharedPreferences for quick access
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('avatar_uri', uploadResp.toString());
        await prefs.setBool('avatar_is_matrix', true);
        print('[Matrix Avatar] Stored in SharedPreferences');

        InAppNotifier.instance.show(
          title: 'Avatar updated',
          variant: InAppNotificationVariant.success,
        );

        // Step 4: Clear cache and reload the avatar to display it
        print('[Matrix Avatar] Clearing cache and reloading avatar');
        _avatarBytes = null;
        _cachedAvatarUri = null;
        _hasLoadedAvatar = false; // Reset flag to allow reload
        
        // Clear static cache for this user
        _avatarCache.remove(userId);
        _avatarUriCache.remove(userId);
        
        // Notify AvatarBloc about the update
        final avatarBloc = context.read<AvatarBloc>();
        avatarBloc.add(AvatarUpdateReceived(
          userId: userId,
          avatarUrl: uploadResp.toString(),
          encryptionKey: key.base64,
          encryptionIv: iv.base64,
          isMatrixUrl: true,
        ));
        
        // Force rebuild to show the new avatar
        setState(() {});
        
        print('[Matrix Avatar] Reload complete');

        // Step 5: Broadcast avatar announcement to all rooms
        print('[Matrix Avatar] Broadcasting avatar announcement to all rooms');
        final avatarService = AvatarAnnouncementService(client);
        await avatarService.broadcastProfPicToAllRooms();
      } else {
        throw Exception('Failed to upload avatar to Matrix');
      }
    } catch (e) {
      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      InAppNotifier.instance.show(
        title: 'Failed to upload avatar',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  /// Wipes the locally stored avatar entry. Used by ProfilePhotoScreen's
  /// "Remove photo" action. Server-side avatar deletion isn't supported by
  /// the current Matrix flow, so we just clear the cached pointer here —
  /// the UI will fall back to the deterministic GridAvatar.
  Future<void> _removeAvatar() async {
    final client = Provider.of<Client>(context, listen: false);
    final userId = client.userID ?? '';
    final secureStorage = const FlutterSecureStorage();

    try {
      await secureStorage.delete(key: 'avatar_$userId');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('avatar_uri');
      await prefs.remove('avatar_is_matrix');
      await prefs.remove('avatar_is_matrix_$userId');
      await prefs.remove('avatar_fallback_$userId');

      _avatarBytes = null;
      _cachedAvatarUri = null;
      _hasLoadedAvatar = false;
      _avatarCache.remove(userId);
      _avatarUriCache.remove(userId);

      if (!mounted) return;
      setState(() {
        _avatarUpdateCounter += 1;
      });

      InAppNotifier.instance.show(
        title: 'Profile photo removed',
        variant: InAppNotificationVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      InAppNotifier.instance.show(
        title: 'Failed to remove avatar',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }

  Future<void> _loadCachedAvatar() async {
    final client = Provider.of<Client>(context, listen: false);
    final userId = client.userID ?? '';
    
    // Check static cache first
    if (_avatarCache.containsKey(userId)) {
      print('[Avatar Load] Using avatar from static cache');
      setState(() {
        _avatarBytes = _avatarCache[userId];
        _cachedAvatarUri = _avatarUriCache[userId];
        _isLoadingAvatar = false;
      });
      return;
    }
    
    // Only load once per widget lifecycle
    if (_hasLoadedAvatar) {
      print('[Avatar Load] Already attempted load, skipping');
      return;
    }
    
    print('[Avatar Load] Starting avatar load - not in cache');
    _hasLoadedAvatar = true;
    
    try {
      setState(() {
        _isLoadingAvatar = true;
      });

      final secureStorage = FlutterSecureStorage();
      
      // First check if custom server (Matrix avatar)
      final prefs = await SharedPreferences.getInstance();
      final isMatrixAvatar = prefs.getBool('avatar_is_matrix') ?? false;
      
      if (isMatrixAvatar) {
        // For custom servers, check secure storage for encrypted avatar
        print('[Matrix Avatar Load] Loading avatar for Matrix user: $userId');
        
        final avatarDataStr = await secureStorage.read(key: 'avatar_$userId');
        if (avatarDataStr != null) {
          final avatarData = json.decode(avatarDataStr);
          final uri = avatarData['uri'];
          final keyBase64 = avatarData['key'];
          final ivBase64 = avatarData['iv'];
          
          if (uri != null && keyBase64 != null && ivBase64 != null) {
            // Parse mxc:// URL to get server name and media ID
            final mxcUri = Uri.parse(uri);
            final serverName = mxcUri.host;
            final mediaId = mxcUri.path.substring(1); // Remove leading /
            
            print('[Matrix Avatar Load] Downloading encrypted file from Matrix: server=$serverName, mediaId=$mediaId');
            print('[Matrix Avatar Load] Client logged in: ${client.isLogged()}');
            print('[Matrix Avatar Load] Access token present: ${client.accessToken != null}');
            print('[Matrix Avatar Load] Homeserver: ${client.homeserver}');

            Uint8List fileData;
            try {
              final file = await client.getContent(serverName, mediaId);
              fileData = file.data;
              print('[Matrix Avatar Load] Downloaded ${fileData.length} encrypted bytes');
            } catch (e) {
              print('[Matrix Avatar Load] Failed to download: $e');
              print('[Matrix Avatar Load] Error details: ${e.toString()}');
              // Re-throw to preserve original error handling
              rethrow;
            }

            // Decrypt
            final key = encrypt.Key.fromBase64(keyBase64);
            final iv = encrypt.IV.fromBase64(ivBase64);
            final encrypter = encrypt.Encrypter(encrypt.AES(key));

            // Convert to Encrypted object and decrypt
            final encrypted = encrypt.Encrypted(fileData);
            final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
            
            final avatarBytes = Uint8List.fromList(decrypted);
            
            // Update static cache
            _avatarCache[userId] = avatarBytes;
            _avatarUriCache[userId] = uri;
            
            setState(() {
              _avatarBytes = avatarBytes;
              _cachedAvatarUri = uri; // Cache the Matrix URI
              _isLoadingAvatar = false;
            });
            print('[Matrix Avatar Load] Avatar decrypted and set in UI and cache');
          } else {
            print('[Matrix Avatar Load] Missing encryption keys or URI');
            setState(() {
              _isLoadingAvatar = false;
            });
          }
        } else {
          print('[Matrix Avatar Load] No avatar data in secure storage');
          setState(() {
            _isLoadingAvatar = false;
          });
        }
      } else {
        // For default servers, check secure storage
        final avatarDataStr = await secureStorage.read(key: 'avatar_$userId');
        if (avatarDataStr != null) {
          final avatarData = json.decode(avatarDataStr);
          final uri = avatarData['uri'];
          final keyBase64 = avatarData['key'];
          final ivBase64 = avatarData['iv'];
          
          if (uri != null && keyBase64 != null && ivBase64 != null) {
            // Download encrypted file
            // print('Downloading avatar from: $uri');
            final response = await http.get(Uri.parse(uri));
            // print('Response status: ${response.statusCode}');
            // print('Response content-type: ${response.headers['content-type']}');
            
            if (response.statusCode == 200) {
              // Check if response is HTML (error page)
              final contentType = response.headers['content-type'] ?? '';
              if (contentType.contains('text/html')) {
                // print('Error: Received HTML instead of image data');
                // print('Response body: ${response.body.substring(0, 200)}...');
                setState(() {
                  _isLoadingAvatar = false;
                });
                return;
              }
              
              // Decrypt
              final key = encrypt.Key.fromBase64(keyBase64);
              final iv = encrypt.IV.fromBase64(ivBase64);
              final encrypter = encrypt.Encrypter(encrypt.AES(key));
              
              // Convert response bytes to Encrypted object
              final encrypted = encrypt.Encrypted(response.bodyBytes);
              final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
              
              final avatarBytes = Uint8List.fromList(decrypted);
              
              // Update static cache
              _avatarCache[userId] = avatarBytes;
              _avatarUriCache[userId] = uri;
              
              setState(() {
                _avatarBytes = avatarBytes;
                _cachedAvatarUri = uri; // Cache the URI
                _isLoadingAvatar = false;
              });
            } else {
              print('Failed to download avatar: ${response.statusCode}');
              setState(() {
                _isLoadingAvatar = false;
              });
            }
          } else {
            setState(() {
              _isLoadingAvatar = false;
            });
          }
        } else {
          setState(() {
            _isLoadingAvatar = false;
          });
        }
      }
    } catch (e) {
      print('Error loading cached avatar: $e');
      setState(() {
        _isLoadingAvatar = false;
      });
    }
  }


  Future<void> _deleteAccount() async {

    // first check which server in use
    final client = Provider.of<Client>(context, listen: false);
    final sharedPreferences = await SharedPreferences.getInstance();
    final serverType = sharedPreferences.getString('serverType');
    final homeserver = await client.homeserver;
    final defaultHomeserver = await dotenv.env['MATRIX_SERVER_URL'];
    if (serverType == 'default' || (homeserver?.toString().trim() == defaultHomeserver?.trim())) {
      _deactivateSMSAccount();
      return;
    }


    // currently uses API directly versus SDK
    // due to issues with SDK

    // Step 1: Confirm deactivation
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildDeleteConfirmationDialog(isCustomServer: true),
    );

    if (confirmed != true) return;

    // Step 2: Prompt for password
    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildPasswordConfirmationDialog(passwordController),
    );

    if (password == null) return;

    // Step 3: Use `http` to send the deactivation request
    final url = Uri.parse('${client.homeserver}/_matrix/client/v3/account/deactivate');
    final authData = {
      "type": "m.login.password",
      "user": client.userID,
      "password": password,
    };
    final body = jsonEncode({
      "auth": authData,
      "erase": true
    });

    try {
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer ${client.accessToken}",
          "Content-Type": "application/json"
        },
        body: body,
      );

      if (response.statusCode == 200) {
        print("Account successfully deleted.");
        final client = Provider.of<Client>(context, listen: false);
        final databaseService = Provider.of<DatabaseService>(context, listen: false);
        final syncManager = Provider.of<SyncManager>(context, listen: false);

        final locationManager = Provider.of<LocationManager>(context, listen: false);
        locationManager.stopTracking();
        syncManager.stopSync();
        databaseService.deleteAndReinitialize();
        await sharedPreferences.clear();


        try {
          if (client.isLogged()) {
            client.logout();
          } else {
            // do nothing
          }
        } catch (e) {
          print("error logging out post account deletion: $e");
        }

        Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
      } else {
        print("Failed to delete account: ${response.body}");
        InAppNotifier.instance.show(
          title: 'Failed to delete account',
          message: response.body,
          variant: InAppNotificationVariant.error,
        );
      }
    } catch (e) {
      InAppNotifier.instance.show(
        title: 'Error',
        message: '$e',
        variant: InAppNotificationVariant.error,
      );
    }
  }



  Future<void> _launchURL(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  Widget _buildInfoBubble(String label, String value) {
    return GestureDetector(
      onTap: () => _showInfoModal(label, value),
      child: Container(
        width: double.infinity, // Ensures the bubble takes the full width
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        margin: EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.1), // Lighter background for contrast
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
                overflow: TextOverflow.ellipsis, // Ellipsis if text overflows
              ),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCustom = isCustomHomeserver();

    return Scaffold(
      backgroundColor: context.gridColors.bg,
      appBar: AppBar(
        backgroundColor: context.gridColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.gridColors.text,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.getFont(
            'Geist',
            color: context.gridColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.015,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            // Profile header card
            _buildProfileSection(theme, colorScheme),

            // ── Appearance ──────────────────────────────────
            const GridSectionHeader(text: 'Appearance'),
            _buildSectionCard(
              theme: theme,
              colorScheme: colorScheme,
              children: [
                AnimatedBuilder(
                  animation: ThemeController.instance,
                  builder: (context, _) => _buildInfoRow(
                    icon: Icons.brightness_6_outlined,
                    title: 'Appearance',
                    value: _themeModeLabel(ThemeController.instance.mode),
                    onTap: _openAppearance,
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            ),

            // ── Sharing ─────────────────────────────────────
            const GridSectionHeader(text: 'Sharing'),
            _buildSectionCard(
              theme: theme,
              colorScheme: colorScheme,
              children: [
                _buildToggleOption(
                  icon: Icons.location_on_outlined,
                  title: 'Sharing location',
                  // The screen historically called this "Incognito Mode"; the
                  // redesign inverts the framing so a green toggle == sharing.
                  value: !_incognitoMode,
                  onChanged: (v) => _toggleIncognitoMode(!v),
                  colorScheme: colorScheme,
                ),
                _buildSettingsDivider(),
                _buildInfoRow(
                  icon: Icons.tune_outlined,
                  title: 'Sharing mode',
                  value: _sharingModeLabel(_sharingMode),
                  onTap: _openSharingMode,
                  colorScheme: colorScheme,
                ),
                _buildSettingsDivider(),
                _buildToggleOption(
                  icon: Icons.home_outlined,
                  title: 'Pause sharing at home',
                  subtitle:
                      'Pauses automatically when you cross the geofence',
                  value: _autoPauseAtHome,
                  onChanged: _onAutoPauseAtHomeToggled,
                  colorScheme: colorScheme,
                ),
                if (_autoPauseAtHome && _homeLocationSet) ...[
                  _buildSettingsDivider(),
                  _buildMenuOption(
                    icon: Icons.edit_location_alt_outlined,
                    title: 'Home location',
                    trailing: 'Change',
                    onTap: _changeHomeLocation,
                    colorScheme: colorScheme,
                  ),
                  _buildSettingsDivider(),
                  _buildMenuOption(
                    icon: Icons.location_off_outlined,
                    title: 'Clear home location',
                    onTap: _clearHomeLocation,
                    colorScheme: colorScheme,
                    isDestructive: true,
                  ),
                ],
              ],
            ),

            // ── Privacy & security ──────────────────────────
            const GridSectionHeader(text: 'Privacy & security'),
            _buildSectionCard(
              theme: theme,
              colorScheme: colorScheme,
              children: [
                if (!isCustom) ...[
                  _buildMenuOption(
                    icon: Icons.key_outlined,
                    title: 'Passkeys',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const PasskeyManagementScreen(),
                        ),
                      );
                    },
                    colorScheme: colorScheme,
                  ),
                  _buildSettingsDivider(),
                ],
                _buildInfoRow(
                  icon: Icons.fingerprint_rounded,
                  title: 'Device ID',
                  value: deviceID ?? 'Loading…',
                  onTap: _openEncryptionKeys,
                  colorScheme: colorScheme,
                  mono: true,
                ),
              ],
            ),

            // Subscriptions (still hidden — kept as a flag for parity).
            // Hidden while sat-map provider is offline; re-enable by removing
            // the `false &&` once subscriptions can deliver value again.
            if (false && !isCustom) ...[
              const GridSectionHeader(text: 'Subscription'),
              _buildSectionCard(
                theme: theme,
                colorScheme: colorScheme,
                children: [
                  _buildMenuOption(
                    icon: Icons.credit_card,
                    title: 'Manage subscription',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SubscriptionScreen(),
                        ),
                      );
                    },
                    colorScheme: colorScheme,
                  ),
                ],
              ),
            ],

            // ── About ───────────────────────────────────────
            const GridSectionHeader(text: 'About'),
            _buildSectionCard(
              theme: theme,
              colorScheme: colorScheme,
              children: [
                _buildMenuOption(
                  icon: Icons.code_rounded,
                  title: 'Open source',
                  trailing: 'github.com/Rezivure',
                  onTap: () => _launchURL('https://github.com/Rezivure'),
                  colorScheme: colorScheme,
                ),
                _buildSettingsDivider(),
                _buildMenuOption(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  onTap: () => _launchURL('https://mygrid.app/privacy'),
                  colorScheme: colorScheme,
                ),
                _buildSettingsDivider(),
                _buildMenuOption(
                  icon: FontAwesomeIcons.discord,
                  title: 'Join our Discord',
                  onTap: () => _launchURL('https://discord.gg/cJrQXMn6Hk'),
                  colorScheme: colorScheme,
                ),
                _buildSettingsDivider(),
                _buildMenuOption(
                  icon: Icons.logout_rounded,
                  title: 'Sign out',
                  onTap: _logout,
                  colorScheme: colorScheme,
                  isDestructive: true,
                ),
                _buildSettingsDivider(),
                _buildMenuOption(
                  icon: Icons.delete_forever_outlined,
                  title: 'Delete account',
                  onTap: _deleteAccount,
                  colorScheme: colorScheme,
                  isDestructive: true,
                  isHighRisk: true,
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Footer: mono "Grid vX.X · build XXX" with Grid mark.
            // Easter egg: 5 quick taps opens the hidden Developer Tools screen.
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onFooterTapped,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.gridColors.mint.withOpacity(0.18),
                        border: Border.all(
                          color: context.gridColors.mint,
                          width: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GridMono(
                      _buildFooterText(),
                      color: context.gridColors.text3,
                      size: 11,
                      letterSpacing: 0.04,
                      uppercase: false,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _openEncryptionKeys() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EncryptionKeysScreen(
          deviceId: deviceID,
          identityKey: identityKey,
        ),
      ),
    );
  }

  void _openAppearance() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()),
    );
  }

  void _openSharingMode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SharingModeScreen(
          initial: _sharingMode,
          onChanged: _setSharingMode,
        ),
      ),
    );
  }

  String _themeModeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  String _sharingModeLabel(SharingMode m) => switch (m) {
        SharingMode.light => 'Light',
        SharingMode.balanced => 'Balanced',
        SharingMode.live => 'Live',
      };

  void _openProfilePhoto() {
    final client = Provider.of<Client>(context, listen: false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePhotoScreen(
          userId: client.userID ?? '',
          displayName: _displayName ?? _username ?? 'Grid',
          onTakePhoto: () =>
              _pickAndUploadAvatar(presetSource: ImageSource.camera),
          onChooseFromGallery: () =>
              _pickAndUploadAvatar(presetSource: ImageSource.gallery),
          onRemovePhoto: _removeAvatar,
        ),
      ),
    );
  }

  /// Footer line, e.g. "Grid v3.2 · build 612".
  String _buildFooterText() {
    final version = _appVersion.isEmpty ? '' : _appVersion;
    final build = _buildNumber.isEmpty ? '' : 'build $_buildNumber';
    if (version.isEmpty && build.isEmpty) return 'Grid';
    if (version.isEmpty) return 'Grid · $build';
    if (build.isEmpty) return 'Grid $version';
    return 'Grid $version · $build';
  }

  /// Hairline separator between rows inside a settings group.
  Widget _buildSettingsDivider() {
    return Padding(
      padding: EdgeInsets.only(left: 56),
      child: Divider(
        height: 1,
        thickness: 1,
        color: context.gridColors.hairline,
      ),
    );
  }

  // Helper Methods for New UI
  Widget _buildProfileSection(ThemeData theme, ColorScheme colorScheme) {
    final client = Provider.of<Client>(context, listen: false);
    final handle = _username ?? '';
    final handlePrefix = handle.startsWith('@') ? handle : '@$handle';
    final handleLine = handlePrefix;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.gridColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.gridColors.hairline),
      ),
      child: Row(
        children: [
          // Avatar — 56pt with mint live ring, tap to expand, long-press / edit
          // pencil flow preserved by the camera button trailing.
          GestureDetector(
            onTap: () => _showExpandedAvatar(context),
            child: Hero(
              tag: 'settings_avatar_${client.userID}',
              child: SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // The redesigned GridAvatar renders the deterministic
                    // gradient + ring; UserAvatarBloc still wins when the
                    // user has uploaded a custom image, so we overlay it
                    // inside the ring container.
                    GridAvatar(
                      name: _displayName ?? _username ?? 'Grid',
                      size: 56,
                      ring: true,
                      selfStatus: _incognitoMode
                          ? SelfSharingStatus.paused
                          : SelfSharingStatus.sharing,
                    ),
                    // Live user-uploaded avatar, clipped into the inner disc.
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: ClipOval(
                          child: UserAvatarBloc(
                            userId: client.userID ?? '',
                            size: 54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _displayName ?? 'Unknown User',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(
                          'Geist',
                          color: context.gridColors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.015,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_isEditingDisplayName)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: context.gridColors.mint,
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _editDisplayName,
                        child: Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: context.gridColors.text3,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                GridMono(
                  handleLine,
                  color: context.gridColors.text2,
                  size: 12,
                  letterSpacing: 0.02,
                  uppercase: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Mint QR shortcut. Wired to the avatar picker so the existing
          // upload flow stays reachable (no QR sheet exists yet in this
          // build of the app).
          // TODO: wire to dedicated profile QR sheet when that lands.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openProfilePhoto,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.gridColors.mintFaint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.gridColors.hairline),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: 22,
                  color: context.gridColors.mint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Grouped settings card — wraps a list of rows in the surface card style
  /// used across the redesign. Rows handle their own padding so this widget
  /// just clips and outlines them.
  Widget _buildSectionCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.gridColors.surface,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: context.gridColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildToggleOption({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required Function(bool) onChanged,
    required ColorScheme colorScheme,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: value && enabled ? context.gridColors.mint : context.gridColors.text2,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.getFont(
                      'Geist',
                      color: context.gridColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.01,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.getFont(
                        'Geist',
                        color: context.gridColors.text3,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.005,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              thumbColor: WidgetStateProperty.all(Colors.white),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? context.gridColors.mint
                    : context.gridColors.surface3,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              trackOutlineColor:
                  WidgetStateProperty.all(Colors.transparent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool mono = false,
  }) {
    final displayValue = value.length > 36
        ? '${value.substring(0, 36)}…'
        : value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: context.gridColors.mintFaint,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: context.gridColors.mint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.getFont(
                        'Geist',
                        color: context.gridColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.01,
                      ),
                    ),
                    const SizedBox(height: 2),
                    mono
                        ? GridMono(
                            displayValue,
                            color: context.gridColors.text3,
                            size: 11,
                            letterSpacing: 0.04,
                            uppercase: false,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : Text(
                            displayValue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(
                              'Geist',
                              color: context.gridColors.text3,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.005,
                            ),
                          ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: context.gridColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    String? trailing,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool isDestructive = false,
    bool isHighRisk = false,
    bool enabled = true,
  }) {
    final Color titleColor = isDestructive ? context.gridColors.danger : context.gridColors.text;
    final Color iconColor = isDestructive ? context.gridColors.danger : context.gridColors.text2;

    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.getFont(
                      'Geist',
                      color: titleColor,
                      fontSize: 15,
                      fontWeight: isHighRisk
                          ? FontWeight.w600
                          : FontWeight.w500,
                      letterSpacing: -0.01,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  Text(
                    trailing,
                    style: GoogleFonts.getFont(
                      'Geist',
                      color: context.gridColors.text2,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.005,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: isDestructive
                      ? context.gridColors.danger.withOpacity(0.6)
                      : context.gridColors.text3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsOption({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16, color: color),
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // Modern Delete Account Dialog Methods
  Widget _buildDeleteConfirmationDialog({bool isCustomServer = false}) {
    final bullets = <_DangerBullet>[
      const _DangerBullet(Icons.delete_forever,
          'Your account will be permanently deleted'),
      const _DangerBullet(Icons.group_remove,
          'You will be removed from all groups and contacts'),
      if (isCustomServer)
        const _DangerBullet(
            Icons.storage, 'All your data will be permanently erased'),
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: context.gridColors.surface,
          borderRadius: BorderRadius.circular(GridTokens.rXl),
          border: Border.all(color: context.gridColors.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.gridColors.dangerSoft,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(GridTokens.rXl),
                  topRight: Radius.circular(GridTokens.rXl),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.gridColors.danger.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(GridTokens.rMd),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: context.gridColors.danger,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delete account',
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.015,
                            color: context.gridColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'This action cannot be undone.',
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: context.gridColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Are you sure you want to delete your account?',
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: context.gridColors.text2,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.gridColors.surface2,
                        borderRadius:
                            BorderRadius.circular(GridTokens.rMd),
                        border: Border.all(color: context.gridColors.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < bullets.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  bullets[i].icon,
                                  color: context.gridColors.danger,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    bullets[i].text,
                                    style: GoogleFonts.getFont(
                                      'Geist',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: context.gridColors.text2,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: GridButton(
                      label: 'Cancel',
                      style: GridButtonStyle.secondary,
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GridButton(
                      label: 'Delete',
                      style: GridButtonStyle.danger,
                      onPressed: () => Navigator.pop(context, true),
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

  Widget _buildSMSConfirmationDialog(TextEditingController codeController) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        decoration: BoxDecoration(
          color: context.gridColors.surface,
          borderRadius: BorderRadius.circular(GridTokens.rXl),
          border: Border.all(color: context.gridColors.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.gridColors.dangerSoft,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(GridTokens.rXl),
                  topRight: Radius.circular(GridTokens.rXl),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.gridColors.danger.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(GridTokens.rMd),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.sms_outlined,
                      color: context.gridColors.danger,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm deletion',
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.015,
                            color: context.gridColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Enter SMS verification code',
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: context.gridColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.gridColors.surface2,
                      borderRadius:
                          BorderRadius.circular(GridTokens.rMd),
                      border: Border.all(color: context.gridColors.hairline),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: context.gridColors.text2,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Enter the confirmation code sent to your phone.',
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: context.gridColors.text2,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 4,
                      color: context.gridColors.text,
                    ),
                    cursorColor: context.gridColors.mint,
                    decoration: InputDecoration(
                      hintText: 'Enter code',
                      hintStyle: GoogleFonts.getFont(
                        'Geist',
                        color: context.gridColors.text3,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                      filled: true,
                      fillColor: context.gridColors.surface2,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(GridTokens.rMd),
                        borderSide:
                            BorderSide(color: context.gridColors.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(GridTokens.rMd),
                        borderSide:
                            BorderSide(color: context.gridColors.hairline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(GridTokens.rMd),
                        borderSide: BorderSide(
                          color: context.gridColors.mint,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: GridButton(
                      label: 'Cancel',
                      style: GridButtonStyle.secondary,
                      onPressed: () => Navigator.pop(context, null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GridButton(
                      label: 'Delete',
                      style: GridButtonStyle.danger,
                      onPressed: () =>
                          Navigator.pop(context, codeController.text),
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

  Widget _buildPasswordConfirmationDialog(TextEditingController passwordController) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        decoration: BoxDecoration(
          color: context.gridColors.surface,
          borderRadius: BorderRadius.circular(GridTokens.rXl),
          border: Border.all(color: context.gridColors.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.gridColors.dangerSoft,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(GridTokens.rXl),
                  topRight: Radius.circular(GridTokens.rXl),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.gridColors.danger.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(GridTokens.rMd),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.lock_outline,
                      color: context.gridColors.danger,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm deletion',
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.015,
                            color: context.gridColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Enter your password to continue',
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: context.gridColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.gridColors.surface2,
                      borderRadius:
                          BorderRadius.circular(GridTokens.rMd),
                      border: Border.all(color: context.gridColors.hairline),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: context.gridColors.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This will permanently delete your account and all associated data.',
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: context.gridColors.text2,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    autofocus: true,
                    obscureText: true,
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 15,
                      color: context.gridColors.text,
                    ),
                    cursorColor: context.gridColors.mint,
                    decoration: InputDecoration(
                      hintText: 'Enter your password',
                      hintStyle: GoogleFonts.getFont(
                        'Geist',
                        color: context.gridColors.text3,
                        fontSize: 15,
                      ),
                      filled: true,
                      fillColor: context.gridColors.surface2,
                      prefixIcon: Icon(
                        Icons.lock_outline,
                        color: context.gridColors.text3,
                        size: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(GridTokens.rMd),
                        borderSide:
                            BorderSide(color: context.gridColors.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(GridTokens.rMd),
                        borderSide:
                            BorderSide(color: context.gridColors.hairline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(GridTokens.rMd),
                        borderSide: BorderSide(
                          color: context.gridColors.mint,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: GridButton(
                      label: 'Cancel',
                      style: GridButtonStyle.secondary,
                      onPressed: () => Navigator.pop(context, null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GridButton(
                      label: 'Delete',
                      style: GridButtonStyle.danger,
                      onPressed: () => Navigator.pop(
                          context, passwordController.text),
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

  Widget _buildSignOutDialog() {
    final bullets = <_DangerBullet>[
      const _DangerBullet(
          Icons.location_off, 'Location sharing will be stopped'),
      const _DangerBullet(Icons.sync_disabled,
          "You'll need to sign in again to access your account"),
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        decoration: BoxDecoration(
          color: context.gridColors.surface,
          borderRadius: BorderRadius.circular(GridTokens.rXl),
          border: Border.all(color: context.gridColors.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.gridColors.mintFaint,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(GridTokens.rXl),
                  topRight: Radius.circular(GridTokens.rXl),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.gridColors.mintSoft,
                      borderRadius:
                          BorderRadius.circular(GridTokens.rMd),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.logout,
                      color: context.gridColors.mint,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sign out',
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.015,
                            color: context.gridColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'You can always sign back in',
                          style: GoogleFonts.getFont(
                            'Geist',
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: context.gridColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to sign out?',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: context.gridColors.text2,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.gridColors.surface2,
                      borderRadius:
                          BorderRadius.circular(GridTokens.rMd),
                      border: Border.all(color: context.gridColors.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < bullets.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                bullets[i].icon,
                                color: context.gridColors.text2,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  bullets[i].text,
                                  style: GoogleFonts.getFont(
                                    'Geist',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: context.gridColors.text2,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: GridButton(
                      label: 'Cancel',
                      style: GridButtonStyle.secondary,
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GridButton(
                      label: 'Sign out',
                      icon: Icons.logout,
                      style: GridButtonStyle.danger,
                      onPressed: () => Navigator.pop(context, true),
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
}

class _DangerBullet {
  const _DangerBullet(this.icon, this.text);
  final IconData icon;
  final String text;
}

