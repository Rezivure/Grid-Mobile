import 'package:equatable/equatable.dart';

abstract class InvitationsEvent extends Equatable {
  const InvitationsEvent();

  @override
  List<Object?> get props => [];
}

class LoadInvitations extends InvitationsEvent {}

class AddInvitation extends InvitationsEvent {
  final Map<String, dynamic> invitation;

  const AddInvitation(this.invitation);

  @override
  List<Object?> get props => [invitation];
}

class RemoveInvitation extends InvitationsEvent {
  final String roomId;

  const RemoveInvitation(this.roomId);

  @override
  List<Object?> get props => [roomId];
}

class ClearInvitations extends InvitationsEvent {}

class ProcessSyncInvitation extends InvitationsEvent {
  final String roomId;
  final String inviter;
  final String roomName;
  final List<dynamic>? inviteState;

  const ProcessSyncInvitation({
    required this.roomId,
    required this.inviter,
    required this.roomName,
    this.inviteState,
  });

  @override
  List<Object?> get props => [roomId, inviter, roomName, inviteState];
}