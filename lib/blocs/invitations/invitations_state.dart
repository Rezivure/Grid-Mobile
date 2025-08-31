import 'package:equatable/equatable.dart';

abstract class InvitationsState extends Equatable {
  const InvitationsState();

  @override
  List<Object?> get props => [];
}

class InvitationsInitial extends InvitationsState {}

class InvitationsLoading extends InvitationsState {}

class InvitationsLoaded extends InvitationsState {
  final List<Map<String, dynamic>> invitations;

  const InvitationsLoaded(this.invitations);

  int get totalInvites => invitations.length;

  @override
  List<Object?> get props => [invitations];
}

class InvitationsError extends InvitationsState {
  final String message;

  const InvitationsError(this.message);

  @override
  List<Object?> get props => [message];
}