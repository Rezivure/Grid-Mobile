import 'package:equatable/equatable.dart';

abstract class GroupsEvent extends Equatable {
  const GroupsEvent();

  @override
  List<Object> get props => [];
}

class LoadGroups extends GroupsEvent {}

class RefreshGroups extends GroupsEvent {}

class SearchGroups extends GroupsEvent {
  final String query;
  const SearchGroups(this.query);

  @override
  List<Object> get props => [query];
}

class DeleteGroup extends GroupsEvent {
  final String roomId;
  const DeleteGroup(this.roomId);

  @override
  List<Object> get props => [roomId];
}

class UpdateGroup extends GroupsEvent {
  final String roomId;
  const UpdateGroup(this.roomId);

  @override
  List<Object> get props => [roomId];
}

class LoadGroupMembers extends GroupsEvent {
  final String roomId;
  const LoadGroupMembers(this.roomId);

  @override
  List<Object> get props => [roomId];
}

class UpdateMemberStatus extends GroupsEvent {
  final String roomId;
  final String userId;
  final String status;

  UpdateMemberStatus(this.roomId, this.userId, this.status);

  @override
  List<Object> get props => [roomId, userId, status];
}