import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matrix/matrix.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'avatar_event.dart';
import 'avatar_state.dart';
import '../../services/avatar_cache_service.dart';
import '../../widgets/group_avatar.dart';

class AvatarBloc extends Bloc<AvatarEvent, AvatarState> {
  final Client client;
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();
  final AvatarCacheService cacheService = AvatarCacheService();
  bool _cacheInitialized = false;

  AvatarBloc({required this.client}) : super(const AvatarState()) {
    on<AvatarUpdated>(_onAvatarUpdated);
    on<AvatarUpdateReceived>(_onAvatarUpdateReceived);
    on<GroupAvatarUpdateReceived>(_onGroupAvatarUpdateReceived);
    on<LoadAvatar>(_onLoadAvatar);
    on<ClearAvatarCache>(_onClearAvatarCache);
    on<RefreshAllAvatars>(_onRefreshAllAvatars);
    
    _initializeCache();
  }

  Future<void> _initializeCache() async {
    if (!_cacheInitialized) {
      _cacheInitialized = true;
      await cacheService.initialize();
    }
  }

  Future<void> _onAvatarUpdated(AvatarUpdated event, Emitter<AvatarState> emit) async {
    if (event.avatarData != null) {
      final newCache = Map<String, Uint8List>.from(state.avatarCache);
      final newLastUpdated = Map<String, DateTime>.from(state.lastUpdated);
      
      newCache[event.userId] = event.avatarData!;
      newLastUpdated[event.userId] = DateTime.now();
      
      // Store in persistent cache
      await cacheService.put(event.userId, event.avatarData!);
      
      emit(state.copyWith(
        avatarCache: newCache,
        lastUpdated: newLastUpdated,
        updateCounter: state.updateCounter + 1,
      ));
    }
  }

  Future<void> _onAvatarUpdateReceived(AvatarUpdateReceived event, Emitter<AvatarState> emit) async {
    try {
      print('[AvatarBloc] Processing avatar update for ${event.userId}');
      
      // Update loading state
      final newLoadingStates = Map<String, bool>.from(state.loadingStates);
      newLoadingStates[event.userId] = true;
      emit(state.copyWith(loadingStates: newLoadingStates));
      
      // Store the new avatar data in secure storage
      final avatarData = {
        'uri': event.avatarUrl,
        'key': event.encryptionKey,
        'iv': event.encryptionIv,
      };
      
      await secureStorage.write(
        key: 'avatar_${event.userId}',
        value: json.encode(avatarData),
      );
      
      // Store whether it's a Matrix avatar
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('avatar_is_matrix_${event.userId}', event.isMatrixUrl);
      
      // Download and decrypt the avatar
      Uint8List encryptedData;
      
      if (event.isMatrixUrl) {
        // Download from Matrix
        final mxcUri = Uri.parse(event.avatarUrl);
        final serverName = mxcUri.host;
        final mediaId = mxcUri.path.substring(1);
        
        final file = await client.getContent(serverName, mediaId);
        encryptedData = Uint8List.fromList(file.data);
      } else {
        // Download from R2
        final response = await http.get(Uri.parse(event.avatarUrl));
        if (response.statusCode != 200) {
          throw Exception('Failed to download avatar: ${response.statusCode}');
        }
        encryptedData = response.bodyBytes;
      }
      
      // Decrypt the avatar
      final key = encrypt.Key.fromBase64(event.encryptionKey);
      final iv = encrypt.IV.fromBase64(event.encryptionIv);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypt.Encrypted(encryptedData);
      final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
      
      final avatarBytes = Uint8List.fromList(decrypted);
      
      // Update state and cache
      final newCache = Map<String, Uint8List>.from(state.avatarCache);
      final newLastUpdated = Map<String, DateTime>.from(state.lastUpdated);
      newLoadingStates[event.userId] = false;
      
      newCache[event.userId] = avatarBytes;
      newLastUpdated[event.userId] = DateTime.now();
      
      // Store in persistent cache
      await cacheService.put(event.userId, avatarBytes);
      
      emit(state.copyWith(
        avatarCache: newCache,
        loadingStates: newLoadingStates,
        lastUpdated: newLastUpdated,
        updateCounter: state.updateCounter + 1,
      ));
      
      print('[AvatarBloc] Successfully processed avatar for ${event.userId}');
      
    } catch (e) {
      print('[AvatarBloc] Error processing avatar update: $e');
      
      // Update loading state to false on error
      final newLoadingStates = Map<String, bool>.from(state.loadingStates);
      newLoadingStates[event.userId] = false;
      emit(state.copyWith(loadingStates: newLoadingStates));
    }
  }

  Future<void> _onGroupAvatarUpdateReceived(GroupAvatarUpdateReceived event, Emitter<AvatarState> emit) async {
    try {
      print('[AvatarBloc] Processing group avatar update for room ${event.roomId}');
      
      // Store the new avatar data in secure storage
      final avatarData = {
        'uri': event.avatarUrl,
        'key': event.encryptionKey,
        'iv': event.encryptionIv,
      };
      
      await secureStorage.write(
        key: 'group_avatar_${event.roomId}',
        value: json.encode(avatarData),
      );
      
      // Store whether it's a Matrix avatar
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('group_avatar_is_matrix_${event.roomId}', event.isMatrixUrl);
      
      // Clear the group avatar cache to force reload
      await GroupAvatar.clearCache(event.roomId);
      
      // Force a state update to trigger UI refresh
      emit(state.copyWith(updateCounter: state.updateCounter + 1));
      
      print('[AvatarBloc] Successfully stored group avatar data for room ${event.roomId}');
      
    } catch (e) {
      print('[AvatarBloc] Error processing group avatar update: $e');
    }
  }

  Future<void> _onLoadAvatar(LoadAvatar event, Emitter<AvatarState> emit) async {
    // Check if already cached
    if (state.avatarCache.containsKey(event.userId)) {
      return;
    }
    
    // Check persistent cache
    final cachedAvatar = cacheService.get(event.userId);
    if (cachedAvatar != null) {
      final newCache = Map<String, Uint8List>.from(state.avatarCache);
      newCache[event.userId] = cachedAvatar;
      emit(state.copyWith(
        avatarCache: newCache,
        updateCounter: state.updateCounter + 1,
      ));
      return;
    }
    
    // Load from secure storage
    try {
      final avatarDataStr = await secureStorage.read(key: 'avatar_${event.userId}');
      if (avatarDataStr != null) {
        final avatarData = json.decode(avatarDataStr);
        final uri = avatarData['uri'];
        final keyBase64 = avatarData['key'];
        final ivBase64 = avatarData['iv'];
        
        if (uri != null && keyBase64 != null && ivBase64 != null) {
          final prefs = await SharedPreferences.getInstance();
          final isMatrixAvatar = prefs.getBool('avatar_is_matrix_${event.userId}') ?? false;
          
          add(AvatarUpdateReceived(
            userId: event.userId,
            avatarUrl: uri,
            encryptionKey: keyBase64,
            encryptionIv: ivBase64,
            isMatrixUrl: isMatrixAvatar,
          ));
        }
      }
    } catch (e) {
      print('[AvatarBloc] Error loading avatar for ${event.userId}: $e');
    }
  }

  Future<void> _onClearAvatarCache(ClearAvatarCache event, Emitter<AvatarState> emit) async {
    if (event.userId == null) {
      // Clear all cache
      await cacheService.clear();
      emit(const AvatarState());
    } else {
      // Clear specific user
      await cacheService.remove(event.userId!);
      final newCache = Map<String, Uint8List>.from(state.avatarCache);
      final newLastUpdated = Map<String, DateTime>.from(state.lastUpdated);
      newCache.remove(event.userId);
      newLastUpdated.remove(event.userId);
      
      emit(state.copyWith(
        avatarCache: newCache,
        lastUpdated: newLastUpdated,
        updateCounter: state.updateCounter + 1,
      ));
    }
  }

  Future<void> _onRefreshAllAvatars(RefreshAllAvatars event, Emitter<AvatarState> emit) async {
    // Force refresh by incrementing counter
    emit(state.copyWith(updateCounter: state.updateCounter + 1));
  }
}