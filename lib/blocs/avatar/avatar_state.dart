import 'package:equatable/equatable.dart';
import 'dart:typed_data';

class AvatarState extends Equatable {
  final Map<String, Uint8List> avatarCache;
  final Map<String, bool> loadingStates;
  final Map<String, DateTime> lastUpdated;
  final int updateCounter; // Forces UI updates even when cache is the same
  
  const AvatarState({
    this.avatarCache = const {},
    this.loadingStates = const {},
    this.lastUpdated = const {},
    this.updateCounter = 0,
  });

  AvatarState copyWith({
    Map<String, Uint8List>? avatarCache,
    Map<String, bool>? loadingStates,
    Map<String, DateTime>? lastUpdated,
    int? updateCounter,
  }) {
    return AvatarState(
      avatarCache: avatarCache ?? this.avatarCache,
      loadingStates: loadingStates ?? this.loadingStates,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      updateCounter: updateCounter ?? this.updateCounter,
    );
  }

  Uint8List? getAvatar(String userId) => avatarCache[userId];
  
  bool isLoading(String userId) => loadingStates[userId] ?? false;
  
  DateTime? getLastUpdated(String userId) => lastUpdated[userId];

  @override
  List<Object?> get props => [avatarCache, loadingStates, lastUpdated, updateCounter];
}