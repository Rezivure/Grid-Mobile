import 'package:equatable/equatable.dart';
import 'dart:typed_data';

class AvatarState extends Equatable {
  final Map<String, Uint8List> avatarCache;
  final Map<String, bool> loadingStates;
  final Map<String, DateTime> lastUpdated;
  final Map<String, DateTime> failedAttempts; // Track when avatars failed to load
  final int updateCounter; // Forces UI updates even when cache is the same
  
  const AvatarState({
    this.avatarCache = const {},
    this.loadingStates = const {},
    this.lastUpdated = const {},
    this.failedAttempts = const {},
    this.updateCounter = 0,
  });

  AvatarState copyWith({
    Map<String, Uint8List>? avatarCache,
    Map<String, bool>? loadingStates,
    Map<String, DateTime>? lastUpdated,
    Map<String, DateTime>? failedAttempts,
    int? updateCounter,
  }) {
    return AvatarState(
      avatarCache: avatarCache ?? this.avatarCache,
      loadingStates: loadingStates ?? this.loadingStates,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      updateCounter: updateCounter ?? this.updateCounter,
    );
  }

  Uint8List? getAvatar(String userId) => avatarCache[userId];
  
  bool isLoading(String userId) => loadingStates[userId] ?? false;
  
  DateTime? getLastUpdated(String userId) => lastUpdated[userId];
  
  bool hasRecentlyFailed(String userId) {
    final failedAt = failedAttempts[userId];
    if (failedAt == null) return false;
    // Consider failed if it failed within the last 5 minutes
    return DateTime.now().difference(failedAt).inMinutes < 5;
  }

  @override
  List<Object?> get props => [avatarCache, loadingStates, lastUpdated, failedAttempts, updateCounter];
}