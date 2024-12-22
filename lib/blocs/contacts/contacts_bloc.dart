import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';
import 'package:grid_frontend/blocs/contacts/contacts_state.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';

import '../map/map_event.dart';

class ContactsBloc extends Bloc<ContactsEvent, ContactsState> {
  final RoomService roomService;
  final UserRepository userRepository;
  List<ContactDisplay> _allContacts = []; // Cache for search filtering
  final MapBloc mapBloc;

  ContactsBloc({
    required this.roomService,
    required this.userRepository,
    required this.mapBloc,
  }) : super(ContactsInitial()) {
    on<LoadContacts>(_onLoadContacts);
    on<RefreshContacts>(_onRefreshContacts);
    on<DeleteContact>(_onDeleteContact);
    on<SearchContacts>(_onSearchContacts);
  }

  Future<void> _onLoadContacts(LoadContacts event, Emitter<ContactsState> emit) async {
    emit(ContactsLoading());
    try {
      _allContacts = await _loadContacts();
      emit(ContactsLoaded(_allContacts));
    } catch (e) {
      emit(ContactsError(e.toString()));
    }
  }

  Future<void> _onRefreshContacts(RefreshContacts event, Emitter<ContactsState> emit) async {
    print("ContactsBloc: Handling RefreshContacts event");
    try {
      final updatedContacts = await _loadContacts();
      _allContacts = updatedContacts; // Update the cache
      print("ContactsBloc: Emitting ContactsLoaded with ${updatedContacts.length} contacts");
      emit(ContactsLoaded(List.from(_allContacts))); // Always emit a new state
    } catch (e) {
      print("ContactsBloc: Error in RefreshContacts - $e");
      emit(ContactsError(e.toString()));
    }
  }


  Future<void> _onDeleteContact(DeleteContact event, Emitter<ContactsState> emit) async {
    try {
      final roomId = await userRepository.getDirectRoomForContact(event.userId);
      if (roomId != null) {
        await roomService.leaveRoom(roomId);
        await userRepository.removeContact(event.userId);
        mapBloc.add(RemoveUserLocation(event.userId));
        _allContacts = await _loadContacts();
        emit(ContactsLoaded(_allContacts));
      }
    } catch (e) {
      emit(ContactsError(e.toString()));
    }
  }

  void _onSearchContacts(SearchContacts event, Emitter<ContactsState> emit) {
    if (_allContacts.isEmpty) return;

    if (event.query.isEmpty) {
      emit(ContactsLoaded(_allContacts));
      return;
    }

    final searchTerm = event.query.toLowerCase();
    final filteredContacts = _allContacts.where((contact) {
      return contact.displayName.toLowerCase().contains(searchTerm) ||
          contact.userId.toLowerCase().contains(searchTerm);
    }).toList();

    emit(ContactsLoaded(filteredContacts));
  }

  Future<List<ContactDisplay>> _loadContacts() async {
    final currentUserId = roomService.getMyUserId();
    final directContacts = await userRepository.getDirectContacts();

    return directContacts
        .where((contact) => contact.userId != currentUserId)
        .map((contact) => ContactDisplay(
      userId: contact.userId,
      displayName: contact.displayName ?? 'Unknown User',
      avatarUrl: contact.avatarUrl,
      lastSeen: 'Offline',
    ))
        .toList();
  }
}