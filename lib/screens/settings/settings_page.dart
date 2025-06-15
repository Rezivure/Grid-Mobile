import 'package:flutter/material.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:random_avatar/random_avatar.dart';
import '../../services/sync_manager.dart';
import '/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:grid_frontend/widgets/profile_picture_modal.dart';
import 'package:grid_frontend/services/profile_picture_service.dart';
import 'package:grid_frontend/services/profile_announcement_service.dart';
import 'package:grid_frontend/services/others_profile_service.dart';
import 'package:grid_frontend/widgets/cached_profile_avatar.dart';
import 'package:grid_frontend/providers/profile_picture_provider.dart';
import 'package:path_provider/path_provider.dart';



class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {

  String? deviceID;
  String? identityKey;
  String _selectedProxy = 'None';
  TextEditingController _customProxyController = TextEditingController();
  bool _incognitoMode = false;
  bool _batterySaver = false;
  String? _userID;
  String? _username;
  String? _localpart;
  String? _displayName;
  bool _isEditingDisplayName = false;
  
  // Profile picture related
  final ProfilePictureService _profilePictureService = ProfilePictureService();
  late ProfileAnnouncementService _profileAnnouncementService;
  Uint8List? _profilePictureBytes;
  bool _isUploadingProfilePic = false;
  bool _isLoadingProfilePic = true;
  bool _hasInitializedAvatar = false;
  bool _isInitializing = true;


  @override
  void initState() {
    super.initState();
    _getDeviceAndIdentityKey();
    _loadUser();
    _loadIncognitoState();
    _loadBatterySaverState();
    _loadProfilePicture();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Initialize profile announcement service if not already done
    final client = Provider.of<Client>(context, listen: false);
    _profileAnnouncementService = ProfileAnnouncementService(
      client: client,
      profilePictureService: _profilePictureService,
    );
  }

  bool isCustomHomeserver() {
    final roomService = Provider.of<RoomService>(context, listen: false);
    final homeserver = roomService.getMyHomeserver();
    return utils.isCustomHomeserver(homeserver);
  }
  
  Future<String> _getMatrixAvatarCachePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/matrix_avatar_cache';
  }
  
  Future<Uint8List?> _getCachedMatrixAvatar() async {
    try {
      final cachePath = await _getMatrixAvatarCachePath();
      final cacheFile = File(cachePath);
      if (await cacheFile.exists()) {
        return await cacheFile.readAsBytes();
      }
    } catch (e) {
      print('Error reading cached Matrix avatar: $e');
    }
    return null;
  }
  
  Future<void> _cacheMatrixAvatar(Uint8List bytes) async {
    try {
      final cachePath = await _getMatrixAvatarCachePath();
      final cacheFile = File(cachePath);
      await cacheFile.writeAsBytes(bytes);
    } catch (e) {
      print('Error caching Matrix avatar: $e');
    }
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
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _incognitoMode = prefs.getBool('incognito_mode') ?? false;
    });
  }

  Future<void> _loadBatterySaverState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _batterySaver = prefs.getBool('battery_saver') ?? false;
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Battery Saver Mode: Enabled')),
      );
    } else {
      locationManager.toggleBatterySaverMode(value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Battery Saver Mode: Disabled')),
      );
    }
  }

  Future<void> _toggleIncognitoMode(bool value) async {
    final locationManager = Provider.of<LocationManager>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _incognitoMode = value;
    });

    await prefs.setBool('incognito_mode', value);

    if (value) {
      locationManager.stopTracking();
      await bg.BackgroundGeolocation.stop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Your location is no longer being shared.')),
      );
    } else {
      locationManager.startTracking();
      await bg.BackgroundGeolocation.start();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Your location is being shared with trusted contacts.')),
      );
    }
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
  
  Future<void> _loadProfilePicture() async {
    // Set initial loading state based on homeserver type
    if (!isCustomHomeserver()) {
      setState(() {
        _isLoadingProfilePic = true;
      });
    }
    // For custom homeservers, keep _isInitializing = true until we know if there's an avatar
    
    try {
      if (isCustomHomeserver()) {
        // For custom homeservers, check cache first
        final cachedAvatar = await _getCachedMatrixAvatar();
        if (cachedAvatar != null && mounted) {
          setState(() {
            _profilePictureBytes = cachedAvatar;
            _isInitializing = false;
          });
        }
        
        // Then try to load Matrix avatar from server
        final client = Provider.of<Client>(context, listen: false);
        if (client.userID != null) {
          try {
            final avatarUrl = await client.getAvatarUrl(client.userID!);
            if (avatarUrl != null) {
              // Build the download URL manually
              final homeserverUrl = client.homeserver;
              final mxcParts = avatarUrl.toString().replaceFirst('mxc://', '').split('/');
              if (mxcParts.length == 2) {
                final serverName = mxcParts[0];
                final mediaId = mxcParts[1];
                final downloadUri = Uri.parse('$homeserverUrl/_matrix/media/v3/download/$serverName/$mediaId');
                
                final response = await client.httpClient.get(downloadUri);
                if (response.statusCode == 200 && mounted) {
                  final avatarBytes = response.bodyBytes;
                  // Cache the avatar
                  await _cacheMatrixAvatar(avatarBytes);
                  setState(() {
                    _profilePictureBytes = avatarBytes;
                    _isInitializing = false;
                  });
                } else {
                  // Failed to load avatar, show random avatar if no cache
                  if (mounted && cachedAvatar == null) {
                    setState(() {
                      _isInitializing = false;
                    });
                  }
                }
              } else {
                // Invalid avatar URL format, show random avatar if no cache
                if (mounted && cachedAvatar == null) {
                  setState(() {
                    _isInitializing = false;
                  });
                }
              }
            } else {
              // No avatar set, show random avatar if no cache
              if (mounted && cachedAvatar == null) {
                setState(() {
                  _isInitializing = false;
                });
              }
            }
          } catch (e) {
            print('Error loading Matrix avatar: $e');
            // Error loading avatar, show random avatar if no cache
            if (mounted && cachedAvatar == null) {
              setState(() {
                _isInitializing = false;
              });
            }
          }
        } else {
          // No user ID, show random avatar if no cache
          if (mounted && cachedAvatar == null) {
            setState(() {
              _isInitializing = false;
            });
          }
        }
      } else {
        // For default server, use e2ee profile picture
        final profilePicBytes = await _profilePictureService.getLocalProfilePicture();
        if (profilePicBytes != null && mounted) {
          setState(() {
            _profilePictureBytes = profilePicBytes;
            _isLoadingProfilePic = false;
          });
        } else if (mounted) {
          setState(() {
            _isLoadingProfilePic = false;
          });
        }
      }
    } catch (e) {
      // Silent fail - user will see default avatar
      print('Error loading profile picture: $e');
      if (mounted) {
        setState(() {
          _isLoadingProfilePic = false;
          _isInitializing = false;
        });
      }
    }
  }
  
  Future<void> _handleProfilePictureSelected(File imageFile) async {
    if (isCustomHomeserver()) return; // Only for default server
    
    setState(() {
      _isUploadingProfilePic = true;
    });
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('loginToken');
      
      if (jwtToken == null) {
        throw Exception('No authentication token found');
      }
      
      // Upload the profile picture
      final metadata = await _profilePictureService.uploadProfilePicture(
        imageFile, 
        jwtToken
      );
      
      // Load the cached picture
      await _loadProfilePicture();
      
      // Announce to all active rooms
      await _profileAnnouncementService.announceToAllActiveRooms();
      
      print('Successfully set profile picture');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile picture updated successfully'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Failed to set profile picture: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile picture'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isUploadingProfilePic = false;
      });
    }
  }
  
  void _showProfilePictureModal() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => ProfilePictureModal(
        onImageSelected: _handleProfilePictureSelected,
      ),
    );
  }
  
  void _showMatrixProfilePictureModal() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => ProfilePictureModal(
        onImageSelected: _handleMatrixProfilePictureSelected,
        isCustomHomeserver: true,
      ),
    );
  }
  
  Future<void> _handleMatrixProfilePictureSelected(File imageFile) async {
    setState(() {
      _isUploadingProfilePic = true;
    });
    
    try {
      final client = Provider.of<Client>(context, listen: false);
      final imageBytes = await imageFile.readAsBytes();
      
      // Upload to Matrix media repository
      final mxcUri = await client.uploadContent(
        imageBytes,
        filename: 'avatar.jpg',
        contentType: 'image/jpeg',
      );
      
      // Set as user's avatar
      await client.setAvatarUrl(
        client.userID!,
        mxcUri,
      );
      
      // Update the profile picture immediately after successful upload
      await _cacheMatrixAvatar(imageBytes);
      setState(() {
        _profilePictureBytes = imageBytes;
        _isInitializing = false;
      });
      
      print('Successfully set Matrix profile picture');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile picture updated successfully'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Failed to set Matrix profile picture: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile picture'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isUploadingProfilePic = false;
      });
    }
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('$title copied to clipboard'),
                                  behavior: SnackBarBehavior.floating,
                                ),
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


  // In SettingsPage, update the _logout method:

  Future<void> _logout() async {
    final client = Provider.of<Client>(context, listen: false);
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final sharedPreferences = await SharedPreferences.getInstance();
    final locationManager = Provider.of<LocationManager>(context, listen: false);
    final syncManager = Provider.of<SyncManager>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _buildSignOutDialog(),
    );

    if (confirmed ?? false) {
      try {
        // Stop location tracking first
        locationManager.stopTracking();

        // Clear sync manager state
        await syncManager.clearAllState();
        await syncManager.stopSync();

        // Clear database
        await databaseService.deleteAndReinitialize();
        
        // Clear profile picture data
        await _profilePictureService.clearLocalProfilePicture();
        
        // Clear all profile picture caches
        final profileProvider = Provider.of<ProfilePictureProvider>(context, listen: false);
        profileProvider.clearCache();
        
        // Clear others' profile data
        final othersProfileService = OthersProfileService();
        await othersProfileService.clearAllProfiles();
        
        // Clear Matrix avatar cache if custom homeserver
        if (isCustomHomeserver()) {
          try {
            final cachePath = await _getMatrixAvatarCachePath();
            final cacheFile = File(cachePath);
            if (await cacheFile.exists()) {
              await cacheFile.delete();
            }
          } catch (e) {
            print('Error clearing Matrix avatar cache: $e');
          }
        }

        // Clear shared preferences
        await sharedPreferences.clear();
        
        // Clear secure storage (encryption keys)
        try {
          const secureStorage = FlutterSecureStorage();
          await secureStorage.deleteAll();
        } catch (e) {
          print('Error clearing secure storage: $e');
        }

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


        // Navigate to welcome screen
        Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sign out: $e')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Phone number not found, is this a beta/test account?')),
      );
      return;
    }

    try {
      // Attempt to request deactivation
      final requestSuccess = await authProvider.requestDeactivateAccount(phoneNumber);
      if (!requestSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to request account deactivation')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Confirmation code was not entered')),
        );
        return;
      }

      // Try confirming account deactivation
      final confirmSuccess = await authProvider.confirmDeactivateAccount(phoneNumber, smsCode);
      if (!confirmSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm account deactivation. Please try again.')),
        );
        return;
      }

      // If successful, stop location tracking, syncing, etc.
      locationManager.stopTracking();
      await syncManager.clearAllState();
      await syncManager.stopSync();

      // Clear your local database
      await databaseService.deleteAndReinitialize();
      
      // Clear profile picture data
      await _profilePictureService.clearLocalProfilePicture();
      
      // Clear Matrix avatar cache if custom homeserver
      if (isCustomHomeserver()) {
        try {
          final cachePath = await _getMatrixAvatarCachePath();
          final cacheFile = File(cachePath);
          if (await cacheFile.exists()) {
            await cacheFile.delete();
          }
        } catch (e) {
          print('Error clearing Matrix avatar cache: $e');
        }
      }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start account deactivation process')),
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
                      padding: EdgeInsets.all(20),
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
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.edit,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit Display Name',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onBackground,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Choose how others see you',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onBackground.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Content Section - Scrollable
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Display Name',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onBackground.withOpacity(0.7),
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: hasError 
                                      ? Colors.red.withOpacity(0.5)
                                      : colorScheme.outline.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: TextField(
                                controller: controller,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Enter your display name',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  hintStyle: TextStyle(
                                    color: colorScheme.onSurface.withOpacity(0.4),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.person_outline,
                                    color: colorScheme.onSurface.withOpacity(0.4),
                                    size: 20,
                                  ),
                                  counterText: '${controller.text.trim().length}/14',
                                  counterStyle: TextStyle(
                                    fontSize: 11,
                                    color: hasError 
                                        ? Colors.red 
                                        : colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                                maxLength: 14,
                                onChanged: (value) {
                                  setState(() {
                                    hasError = !isValidName(value);
                                    if (hasError) {
                                      final trimmed = value.trim();
                                      if (trimmed.isEmpty) {
                                        errorText = 'Display name cannot be empty';
                                      } else if (trimmed.length < 3) {
                                        errorText = 'Must be at least 3 characters';
                                      } else if (trimmed.length > 14) {
                                        errorText = 'Must be 14 characters or less';
                                      } else {
                                        errorText = 'Contains invalid characters';
                                      }
                                    } else {
                                      errorText = null;
                                    }
                                  });
                                },
                              ),
                            ),
                            if (errorText != null) ...[
                              SizedBox(height: 6),
                              Text(
                                errorText!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                            SizedBox(height: 12),
                            
                            // Guidelines - More compact
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: colorScheme.primary.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.visibility,
                                    color: colorScheme.primary,
                                    size: 14,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Display names are only visible to your contacts and group members',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.primary.withOpacity(0.8),
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
                      padding: EdgeInsets.all(20),
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
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorScheme.outline.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    hasError 
                                        ? Colors.grey 
                                        : colorScheme.primary,
                                    hasError 
                                        ? Colors.grey.withOpacity(0.8)
                                        : colorScheme.primary.withOpacity(0.8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: hasError ? [] : [
                                  BoxShadow(
                                    color: colorScheme.primary.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextButton(
                                onPressed: hasError ? null : () {
                                  if (isValidName(controller.text)) {
                                    Navigator.pop(context, controller.text.trim());
                                  }
                                },
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Save',
                                  style: TextStyle(
                                    color: hasError 
                                        ? Colors.white.withOpacity(0.5)
                                        : Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
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
          await client.setDisplayName(id, newDisplayName);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('displayName', newDisplayName);
        }

        setState(() {
          _displayName = newDisplayName;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Display name updated successfully'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: colorScheme.primary,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update display name: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isEditingDisplayName = false; // Hide spinner
        });
      }
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
        await _profilePictureService.clearLocalProfilePicture();
        
        // Clear Matrix avatar cache
        try {
          final cachePath = await _getMatrixAvatarCachePath();
          final cacheFile = File(cachePath);
          if (await cacheFile.exists()) {
            await cacheFile.delete();
          }
        } catch (e) {
          print('Error clearing Matrix avatar cache: $e');
        }
        
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: ${response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
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

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.onBackground,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.1),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Section
            _buildProfileSection(theme, colorScheme),
            SizedBox(height: 32),

            // Privacy & Location Section
            _buildSectionCard(
              theme: theme,
              colorScheme: colorScheme,
              title: 'Privacy & Location',
              children: [
                _buildToggleOption(
                  icon: Icons.visibility_off,
                  title: 'Incognito Mode',
                  subtitle: 'Stops all location sharing services',
                  value: _incognitoMode,
                  onChanged: _toggleIncognitoMode,
                  colorScheme: colorScheme,
                ),
                SizedBox(height: 16),
                _buildToggleOption(
                  icon: Icons.battery_saver,
                  title: 'Battery Saver Mode',
                  subtitle: 'Less accurate, but less power consumption',
                  value: _batterySaver,
                  onChanged: _toggleBatterySaver,
                  colorScheme: colorScheme,
                ),
              ],
            ),
            SizedBox(height: 24),

            // Security Information Section
            _buildSectionCard(
              theme: theme,
              colorScheme: colorScheme,
              title: 'Security Information',
              children: [
                _buildInfoRow(
                  icon: Icons.device_hub,
                  title: 'Device ID',
                  value: deviceID ?? 'Loading...',
                  onTap: () => _showInfoModal('Device ID', deviceID ?? 'Loading...'),
                  colorScheme: colorScheme,
                ),
                SizedBox(height: 16),
                _buildInfoRow(
                  icon: Icons.key,
                  title: 'Identity Key',
                  value: identityKey ?? 'Loading...',
                  onTap: () => _showInfoModal('Identity Key', identityKey ?? 'Loading...'),
                  colorScheme: colorScheme,
                ),
              ],
            ),
            SizedBox(height: 24),

            // Support & Information Section
            _buildSectionCard(
              theme: theme,
              colorScheme: colorScheme,
              title: 'Support & Information',
              children: [
                _buildMenuOption(
                  icon: Icons.info_outline,
                  title: 'About Grid',
                  subtitle: 'Learn more about the app',
                  onTap: () => _launchURL('https://mygrid.app/about'),
                  colorScheme: colorScheme,
                ),
                SizedBox(height: 16),
                _buildMenuOption(
                  icon: Icons.shield_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'How we protect your data',
                  onTap: () => _launchURL('https://mygrid.app/privacy'),
                  colorScheme: colorScheme,
                ),
                SizedBox(height: 16),
                _buildMenuOption(
                  icon: Icons.feedback_outlined,
                  title: 'Send Feedback',
                  subtitle: 'Help us improve Grid',
                  onTap: () => _launchURL('https://mygrid.app/feedback'),
                  colorScheme: colorScheme,
                ),
                SizedBox(height: 16),
                _buildMenuOption(
                  icon: Icons.report_outlined,
                  title: 'Report Abuse',
                  subtitle: 'Report inappropriate behavior',
                  onTap: () => _launchURL('https://mygrid.app/report'),
                  colorScheme: colorScheme,
                ),
              ],
            ),
            SizedBox(height: 32),

            // Account Actions Section
            _buildSectionCard(
              theme: theme,
              colorScheme: colorScheme,
              title: 'Account Actions',
              children: [
                _buildMenuOption(
                  icon: Icons.logout,
                  title: 'Sign Out',
                  subtitle: 'Sign out of your account',
                  onTap: _logout,
                  colorScheme: colorScheme,
                  isDestructive: true,
                ),
                SizedBox(height: 16),
                _buildMenuOption(
                  icon: Icons.delete_forever,
                  title: 'Delete Account',
                  subtitle: 'Permanently delete your account',
                  onTap: _deleteAccount,
                  colorScheme: colorScheme,
                  isDestructive: true,
                  isHighRisk: true,
                ),
              ],
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // Helper Methods for New UI
  Widget _buildProfileSection(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: colorScheme.primary.withOpacity(0.1),
                child: (_isInitializing && isCustomHomeserver())
                    ? SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary.withOpacity(0.5),
                        ),
                      )
                    : _profilePictureBytes != null
                        ? ClipOval(
                            child: Image.memory(
                              _profilePictureBytes!,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          )
                        : (_isLoadingProfilePic && !isCustomHomeserver()
                            ? SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary.withOpacity(0.5),
                                ),
                              )
                            : RandomAvatar(
                                _localpart ?? 'Unknown User',
                                height: 80,
                                width: 80,
                              )),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _isUploadingProfilePic ? null : (isCustomHomeserver() ? _showMatrixProfilePictureModal : _showProfilePictureModal),
                  child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
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
                      child: _isUploadingProfilePic
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            )
                          : Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _displayName ?? 'Unknown User',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onBackground,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(width: 8),
              if (_isEditingDisplayName)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              else
                GestureDetector(
                  onTap: _editDisplayName,
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '@$_username',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: value
                  ? colorScheme.primary.withOpacity(0.15)
                  : colorScheme.outline.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: value ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.6),
              size: 20,
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
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: colorScheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: colorScheme.primary,
                size: 20,
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
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    value.length > 30 ? '${value.substring(0, 30)}...' : value,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.6),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.visibility,
              color: colorScheme.onSurface.withOpacity(0.4),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool isDestructive = false,
    bool isHighRisk = false,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    final iconColor = isDestructive
        ? (isHighRisk ? Colors.red.shade700 : Colors.red.shade600)
        : colorScheme.primary;
    final textColor = isDestructive
        ? (isHighRisk ? Colors.red.shade700 : Colors.red.shade600)
        : colorScheme.onSurface;
    final subtitleColor = isDestructive
        ? (isHighRisk ? Colors.red.shade500 : Colors.red.shade400)
        : colorScheme.onSurface.withOpacity(0.6);

    // Better colors for dark mode
    final backgroundColor = isDestructive
        ? (isDarkMode 
            ? (isHighRisk ? Colors.red.shade900.withOpacity(0.3) : Colors.red.shade900.withOpacity(0.2))
            : (isHighRisk ? Colors.red.shade50 : Colors.red.shade50))
        : colorScheme.surface;
        
    final borderColor = isDestructive
        ? (isDarkMode 
            ? (isHighRisk ? Colors.red.shade700.withOpacity(0.4) : Colors.red.shade700.withOpacity(0.3))
            : (isHighRisk ? Colors.red.shade200 : Colors.red.shade200))
        : colorScheme.outline.withOpacity(0.15);
        
    final iconBackgroundColor = isDestructive
        ? (isDarkMode 
            ? (isHighRisk ? Colors.red.shade800.withOpacity(0.4) : Colors.red.shade800.withOpacity(0.3))
            : (isHighRisk ? Colors.red.shade100 : Colors.red.shade50))
        : colorScheme.primary.withOpacity(0.1);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconBackgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
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
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: isDestructive
                  ? iconColor.withOpacity(0.6)
                  : colorScheme.onSurface.withOpacity(0.4),
              size: 16,
            ),
          ],
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.6,
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
            // Header Section with Warning
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.red.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.warning,
                      color: Colors.red,
                      size: 28,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delete Account',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'This action cannot be undone',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red.withOpacity(0.8),
                          ),
                        ),
                      ],
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
                      'Are you sure you want to delete your account?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onBackground,
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // Warning cards
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.delete_forever, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your account will be permanently deleted',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.group_remove, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'You will be removed from all groups and contacts',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isCustomServer) ...[
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.storage, color: Colors.red, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'All your data will be permanently erased',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.red,
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
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Delete Account',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
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
  }

  Widget _buildSMSConfirmationDialog(TextEditingController codeController) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
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
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.red.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.sms,
                      color: Colors.red,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm Deletion',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Enter SMS verification code',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Content Section
            Container(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            'Enter the confirmation code sent to your phone',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.primary,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'SMS Code',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onBackground.withOpacity(0.7),
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter code',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(16),
                        hintStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ),
                  ),
                ],
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
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, codeController.text),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Delete Account',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
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
  }

  Widget _buildPasswordConfirmationDialog(TextEditingController passwordController) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
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
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.red.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.lock,
                      color: Colors.red,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm Deletion',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Enter your password to continue',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Content Section
            Container(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning,
                          color: Colors.red,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This will permanently delete your account and all associated data',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.red,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Password',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onBackground.withOpacity(0.7),
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: passwordController,
                      obscureText: true,
                      style: TextStyle(
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(16),
                        hintStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4),
                        ),
                        prefixIcon: Icon(
                          Icons.lock_outline,
                          color: colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ),
                  ),
                ],
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
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, passwordController.text),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Delete',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
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
  }

  Widget _buildSignOutDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
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
                      Icons.logout,
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
                          'Sign Out',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onBackground,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'You can always sign back in',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onBackground.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Content Section
            Container(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to sign out?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onBackground,
                    ),
                  ),
                  SizedBox(height: 16),
                  
                  // Info card
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.location_off,
                              color: colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Location sharing will be stopped',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.sync_disabled,
                              color: colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You\'ll need to sign in again to access your account',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
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
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.logout,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Sign Out',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ],
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
  }
}
