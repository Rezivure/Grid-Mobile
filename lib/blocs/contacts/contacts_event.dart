import 'package:equatable/equatable.dart';

abstract class ContactsEvent extends Equatable {
  @override
  List<Object> get props => [];
}

class LoadContacts extends ContactsEvent {}

class RefreshContacts extends ContactsEvent {}

class DeleteContact extends ContactsEvent {
  final String userId;

  DeleteContact(this.userId);

  @override
  List<Object> get props => [userId];
}

class SearchContacts extends ContactsEvent {
  final String query;

  SearchContacts(this.query);

  @override
  List<Object> get props => [query];
}