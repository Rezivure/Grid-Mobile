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
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:grid_frontend/utilities/utils.dart' as utils;
import 'package:matrix/matrix.dart' hide Room;
import 'package:provider/provider.dart';
import 'group_avatar.dart';
import 'user_avatar.dart';
import 'package:grid_frontend/services/avatar_announcement_service.dart';

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

class _GroupProfileModalState extends State<GroupProfileModal> with TickerProviderStateMixin {
  bool _copied = false;
  bool _alwaysShare = false;
  bool _isEditingPreferences = false;
  List<SharingWindow> _sharingWindows = [];
  bool _membersExpanded = false;
  
  // Group avatar state
  static final Map<String, Uint8List> _groupAvatarCache = {};
  Uint8List? _groupAvatarBytes;
  bool _isLoadingGroupAvatar = false;
  bool _hasLoadedGroupAvatar = false;
  bool _isCurrentUserAdmin = false;
  
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
    _loadSharingPreferences();
    _checkAdminStatus();
    _loadGroupAvatar();
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

  void _checkAdminStatus() {
    final client = widget.roomService.client;
    final currentUserId = client.userID ?? '';
    final powerLevel = widget.roomService.getUserPowerLevel(
      widget.room.roomId,
      currentUserId,
    );
    setState(() {
      _isCurrentUserAdmin = powerLevel == 100;
    });
  }

  Future<void> _loadGroupAvatar() async {
    final roomId = widget.room.roomId;
    
    // Check static cache first
    if (_groupAvatarCache.containsKey(roomId)) {
      print('[Group Avatar Load] Using avatar from static cache');
      setState(() {
        _groupAvatarBytes = _groupAvatarCache[roomId];
        _isLoadingGroupAvatar = false;
      });
      return;
    }
    
    if (_hasLoadedGroupAvatar) {
      print('[Group Avatar Load] Already attempted load, skipping');
      return;
    }
    
    print('[Group Avatar Load] Starting avatar load for room: $roomId');
    _hasLoadedGroupAvatar = true;
    
    try {
      setState(() {
        _isLoadingGroupAvatar = true;
      });

      final secureStorage = FlutterSecureStorage();
      final prefs = await SharedPreferences.getInstance();
      
      // Check if it's a Matrix avatar or encrypted avatar
      final isMatrixAvatar = prefs.getBool('group_avatar_is_matrix_$roomId') ?? false;
      
      // Check secure storage for avatar data
      final avatarDataStr = await secureStorage.read(key: 'group_avatar_$roomId');
      if (avatarDataStr != null) {
        final avatarData = json.decode(avatarDataStr);
        final uri = avatarData['uri'];
        final keyBase64 = avatarData['key'];
        final ivBase64 = avatarData['iv'];
        
        if (uri != null && keyBase64 != null && ivBase64 != null) {
          if (isMatrixAvatar) {
            // Download from Matrix
            final client = Provider.of<Client>(context, listen: false);
            final mxcUri = Uri.parse(uri);
            final serverName = mxcUri.host;
            final mediaId = mxcUri.path.substring(1);
            
            print('[Group Avatar Load] Downloading encrypted file from Matrix');
            final file = await client.getContent(serverName, mediaId);
            
            // Decrypt
            final key = encrypt.Key.fromBase64(keyBase64);
            final iv = encrypt.IV.fromBase64(ivBase64);
            final encrypter = encrypt.Encrypter(encrypt.AES(key));
            final encrypted = encrypt.Encrypted(Uint8List.fromList(file.data));
            final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
            
            final avatarBytes = Uint8List.fromList(decrypted);
            _groupAvatarCache[roomId] = avatarBytes;
            
            setState(() {
              _groupAvatarBytes = avatarBytes;
              _isLoadingGroupAvatar = false;
            });
          } else {
            // Download from R2
            print('[Group Avatar Load] Downloading from R2: $uri');
            final response = await http.get(Uri.parse(uri));
            
            if (response.statusCode == 200) {
              // Decrypt
              final key = encrypt.Key.fromBase64(keyBase64);
              final iv = encrypt.IV.fromBase64(ivBase64);
              final encrypter = encrypt.Encrypter(encrypt.AES(key));
              final encrypted = encrypt.Encrypted(response.bodyBytes);
              final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
              
              final avatarBytes = Uint8List.fromList(decrypted);
              _groupAvatarCache[roomId] = avatarBytes;
              
              setState(() {
                _groupAvatarBytes = avatarBytes;
                _isLoadingGroupAvatar = false;
              });
            } else {
              setState(() {
                _isLoadingGroupAvatar = false;
              });
            }
          }
        } else {
          setState(() {
            _isLoadingGroupAvatar = false;
          });
        }
      } else {
        setState(() {
          _isLoadingGroupAvatar = false;
        });
      }
    } catch (e) {
      print('[Group Avatar Load] Error: $e');
      setState(() {
        _isLoadingGroupAvatar = false;
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

  Future<void> _pickAndUploadGroupAvatar() async {
    try {
      // Pick image with heavy compression for small avatar
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
        maxWidth: 256,
        maxHeight: 256,
      );
      
      if (image == null) return;
      
      setState(() {
        _isLoadingGroupAvatar = true;
      });
      
      // Show encryption notice modal
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            final colorScheme = Theme.of(context).colorScheme;
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            color: colorScheme.primary,
                            strokeWidth: 3,
                          ),
                        ),
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
            );
          },
        );
      }
      
      // Crop the image
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Group Photo',
            toolbarColor: Theme.of(context).colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: Theme.of(context).colorScheme.primary,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: false,
            aspectRatioPresets: [CropAspectRatioPreset.square],
            cropStyle: CropStyle.circle,
          ),
          IOSUiSettings(
            title: 'Crop Group Photo',
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
      
      if (croppedFile == null) {
        if (mounted) Navigator.of(context).pop();
        setState(() {
          _isLoadingGroupAvatar = false;
        });
        return;
      }
      
      // Check if using custom homeserver
      final client = Provider.of<Client>(context, listen: false);
      final homeserver = client.homeserver.toString();
      final isCustomServer = utils.isCustomHomeserver(homeserver);
      
      if (isCustomServer) {
        await _uploadGroupAvatarToMatrix(croppedFile.path);
      } else {
        await _uploadGroupAvatarToR2(croppedFile.path);
      }
      
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      print('[Group Avatar Upload] Error: $e');
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload group avatar: $e')),
        );
      }
      setState(() {
        _isLoadingGroupAvatar = false;
      });
    }
  }
  
  Future<void> _uploadGroupAvatarToR2(String imagePath) async {
    try {
      // Generate encryption key and IV
      final key = encrypt.Key.fromSecureRandom(32);
      final iv = encrypt.IV.fromSecureRandom(16);
      
      // Read and encrypt the image
      final imageBytes = await File(imagePath).readAsBytes();
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encryptBytes(imageBytes, iv: iv);
      
      // Get JWT token
      final prefs = await SharedPreferences.getInstance();
      final jwt = prefs.getString('loginToken');
      
      if (jwt == null) {
        throw Exception('No authentication token found');
      }
      
      // Upload to middleware
      final middlewareUrl = dotenv.env['GAUTH_URL'] ?? 'https://gauth.mygrid.app';
      print('[Group Avatar Upload] Using middleware URL: $middlewareUrl/upload-profile-pic');
      print('[Group Avatar Upload] JWT token present: ${jwt != null}');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$middlewareUrl/upload-profile-pic'),
      );
      
      // Add JWT token
      request.headers['Authorization'] = 'Bearer $jwt';
      print('[Group Avatar Upload] Authorization header set');
      
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
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final filename = responseData['filename'];
        
        // Construct CDN URL
        final cdnBaseUrl = dotenv.env['PROFILE_PIC_CDN_URL'] ?? 'https://profile-store.mygrid.app';
        final cdnUrl = '$cdnBaseUrl/$filename';
        
        print('[Group Avatar Upload] Success! CDN URL: $cdnUrl');
        
        // Store in secure storage
        final secureStorage = FlutterSecureStorage();
        final avatarData = {
          'uri': cdnUrl,
          'key': key.base64,
          'iv': iv.base64,
        };
        
        await secureStorage.write(
          key: 'group_avatar_${widget.room.roomId}',
          value: json.encode(avatarData),
        );
        
        // Mark as non-matrix avatar
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('group_avatar_is_matrix_${widget.room.roomId}', false);
        
        // Update cache and UI
        final decryptedBytes = Uint8List.fromList(imageBytes);
        _groupAvatarCache[widget.room.roomId] = decryptedBytes;
        
        // Clear GroupAvatar widget cache
        GroupAvatar.clearCache(widget.room.roomId);
        
        setState(() {
          _groupAvatarBytes = decryptedBytes;
          _isLoadingGroupAvatar = false;
        });
        
        // Announce group avatar update to this room
        print('[Group Avatar Upload] Announcing group avatar to room ${widget.room.roomId}');
        print('[Group Avatar Upload] Room name: ${widget.room.name}');
        final client = Provider.of<Client>(context, listen: false);
        final avatarService = AvatarAnnouncementService(client);
        await avatarService.announceGroupAvatarToRoom(widget.room.roomId);
        print('[Group Avatar Upload] Announcement sent');
      } else {
        print('[Group Avatar Upload R2] Failed with status ${response.statusCode}');
        print('[Group Avatar Upload R2] Response body: ${response.body}');
        throw Exception('Upload failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('[Group Avatar Upload R2] Error: $e');
      rethrow;
    }
  }
  
  Future<void> _uploadGroupAvatarToMatrix(String imagePath) async {
    try {
      // Generate encryption key and IV
      final key = encrypt.Key.fromSecureRandom(32);
      final iv = encrypt.IV.fromSecureRandom(16);
      
      // Read and encrypt the image
      final imageBytes = await File(imagePath).readAsBytes();
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encryptBytes(imageBytes, iv: iv);
      
      // Upload to Matrix media store
      final client = Provider.of<Client>(context, listen: false);
      
      print('[Group Avatar Upload Matrix] Uploading encrypted file to Matrix media store');
      final uploadResponse = await client.uploadContent(
        encrypted.bytes,
        filename: 'group_avatar_${DateTime.now().millisecondsSinceEpoch}.enc',
        contentType: 'application/octet-stream',
      );
      
      final mxcUri = uploadResponse.toString();
      print('[Group Avatar Upload Matrix] Uploaded to: $mxcUri');
      
      // Store encryption keys in secure storage
      final secureStorage = FlutterSecureStorage();
      final avatarData = {
        'uri': mxcUri,
        'key': key.base64,
        'iv': iv.base64,
      };
      
      await secureStorage.write(
        key: 'group_avatar_${widget.room.roomId}',
        value: json.encode(avatarData),
      );
      
      // Mark as matrix avatar
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('group_avatar_is_matrix_${widget.room.roomId}', true);
      
      // Update cache and UI
      final decryptedBytes = Uint8List.fromList(imageBytes);
      _groupAvatarCache[widget.room.roomId] = decryptedBytes;
      
      // Clear GroupAvatar widget cache
      GroupAvatar.clearCache(widget.room.roomId);
      
      setState(() {
        _groupAvatarBytes = decryptedBytes;
        _isLoadingGroupAvatar = false;
      });
      
      // Announce group avatar update to this room
      print('[Group Avatar Upload Matrix] Announcing group avatar to room ${widget.room.roomId}');
      print('[Group Avatar Upload Matrix] Room name: ${widget.room.name}');
      final avatarService = AvatarAnnouncementService(client);
      await avatarService.announceGroupAvatarToRoom(widget.room.roomId);
      print('[Group Avatar Upload Matrix] Announcement sent');
    } catch (e) {
      print('[Group Avatar Upload Matrix] Error: $e');
      rethrow;
    }
  }

  Widget _buildModernHeader() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return _buildModernCard(
      child: Row(
        children: [
          // Modern avatar with subtle glow
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
            child: Stack(
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: _groupAvatarBytes != null
                      ? ClipOval(
                          child: Image.memory(
                            _groupAvatarBytes!,
                            fit: BoxFit.cover,
                            width: 72,
                            height: 72,
                          ),
                        )
                      : TriangleAvatars(userIds: widget.room.members),
                ),
                if (_isLoadingGroupAvatar)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_isCurrentUserAdmin && !_isLoadingGroupAvatar)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _pickAndUploadGroupAvatar,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: colorScheme.onPrimary,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
                    child: UserAvatar(
                      userId: member.userId,
                      size: 44,
                    ),
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