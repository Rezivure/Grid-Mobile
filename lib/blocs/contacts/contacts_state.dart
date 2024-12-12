// contacts_state.dart
import 'package:equatable/equatable.dart';
import 'package:grid_frontend/models/contact_display.dart';

abstract class ContactsState extends Equatable {
  @override
  List<Object> get props => [];
}

class ContactsInitial extends ContactsState {}

class ContactsLoading extends ContactsState {}

class ContactsLoaded extends ContactsState {
  final List<ContactDisplay> contacts;

  ContactsLoaded(this.contacts);

  @override
  List<Object> get props => [contacts];
}

class ContactsError extends ContactsState {
  final String message;

  ContactsError(this.message);

  @override
  List<Object> get props => [message];
}
