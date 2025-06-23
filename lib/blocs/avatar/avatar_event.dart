import 'package:equatable/equatable.dart';
import 'dart:typed_data';

abstract class AvatarEvent extends Equatable {
  const AvatarEvent();

  @override
  List<Object?> get props => [];
}

class AvatarUpdated extends AvatarEvent {
  final String userId;
  final Uint8List? avatarData;
  
  const AvatarUpdated({
    required this.userId,
    this.avatarData,
  });

  @override
  List<Object?> get props => [userId, avatarData];
}

class AvatarUpdateReceived extends AvatarEvent {
  final String userId;
  final String avatarUrl;
  final String encryptionKey;
  final String encryptionIv;
  final bool isMatrixUrl;
  
  const AvatarUpdateReceived({
    required this.userId,
    required this.avatarUrl,
    required this.encryptionKey,
    required this.encryptionIv,
    required this.isMatrixUrl,
  });

  @override
  List<Object?> get props => [userId, avatarUrl, encryptionKey, encryptionIv, isMatrixUrl];
}

class GroupAvatarUpdateReceived extends AvatarEvent {
  final String roomId;
  final String avatarUrl;
  final String encryptionKey;
  final String encryptionIv;
  final bool isMatrixUrl;
  
  const GroupAvatarUpdateReceived({
    required this.roomId,
    required this.avatarUrl,
    required this.encryptionKey,
    required this.encryptionIv,
    required this.isMatrixUrl,
  });

  @override
  List<Object?> get props => [roomId, avatarUrl, encryptionKey, encryptionIv, isMatrixUrl];
}

class LoadAvatar extends AvatarEvent {
  final String userId;
  
  const LoadAvatar(this.userId);

  @override
  List<Object?> get props => [userId];
}

class ClearAvatarCache extends AvatarEvent {
  final String? userId; // null means clear all
  
  const ClearAvatarCache([this.userId]);

  @override
  List<Object?> get props => [userId];
}

class RefreshAllAvatars extends AvatarEvent {
  const RefreshAllAvatars();
}