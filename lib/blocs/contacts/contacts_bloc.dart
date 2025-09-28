import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';
import 'package:grid_frontend/blocs/contacts/contacts_state.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/models/grid_user.dart';

import '../../providers/user_location_provider.dart';
import '../map/map_event.dart';

class ContactsBloc extends Bloc<ContactsEvent, ContactsState> {
  final RoomService roomService;
  final UserRepository userRepository;
  final LocationRepository locationRepository;
  List<ContactDisplay> _allContacts = []; // Cache for search filtering
  final MapBloc mapBloc;
  final UserLocationProvider userLocationProvider;
  final SharingPreferencesRepository sharingPreferencesRepository;

  ContactsBloc({
    required this.roomService,
    required this.userRepository,
    required this.mapBloc,
    required this.locationRepository,
    required this.userLocationProvider,
    required this.sharingPreferencesRepository,

  }) : super(ContactsInitial()) {
    on<LoadContacts>(_onLoadContacts);
    on<RefreshContacts>(_onRefreshContacts);
    on<DeleteContact>(_onDeleteContact);
    on<SearchContacts>(_onSearchContacts);
  }

  Future<void> _onLoadContacts(LoadContacts event, Emitter<ContactsState> emit) async {
    // Only show loading state if we don't have any contacts yet (initial load)
    final isInitialLoad = _allContacts.isEmpty && state is! ContactsLoaded;

    if (isInitialLoad) {
      emit(ContactsLoading());
    }

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
      print("ContactsBloc: Deleting contact ${event.userId}");
      final roomId = await userRepository.getDirectRoomForContact(event.userId);
      print("ContactsBloc: Found room $roomId for contact ${event.userId}");
      
      if (roomId != null) {
        await roomService.leaveRoom(roomId);
        await userRepository.removeContact(event.userId);
        final wasDeleted = await locationRepository.deleteUserLocationsIfNotInRooms(event.userId);
        if (wasDeleted) {
          userLocationProvider.removeUserLocation(event.userId);
          mapBloc.add(RemoveUserLocation(event.userId));
        }
        await sharingPreferencesRepository.deleteSharingPreferences(event.userId, 'user');
        
        // Reload contacts and update cache
        _allContacts = await _loadContacts();
        print("ContactsBloc: After deletion, loaded ${_allContacts.length} contacts");
        
        // Force emit with new list to ensure UI updates
        emit(ContactsLoaded(List.from(_allContacts)));
      } else {
        print("ContactsBloc: No room found for contact ${event.userId}, cannot delete");
      }
    } catch (e) {
      print("ContactsBloc: Error deleting contact ${event.userId}: $e");
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

    List<ContactDisplay> contactDisplays = [];
    
    for (final contact in directContacts) {
      if (contact.userId == currentUserId) continue;
      
      // Get the direct room for this contact to check membership status
      final directRoomId = await userRepository.getDirectRoomForContact(contact.userId);
      String? membershipStatus;
      
      if (directRoomId != null) {
        // For direct rooms, check stored relationship status first (more reliable for recent invites)
        final relationships = await userRepository.getUserRelationshipsForRoom(directRoomId);
        final userRelationship = relationships.where((r) => r['userId'] == contact.userId).firstOrNull;
        if (userRelationship != null) {
          final storedStatus = userRelationship['membershipStatus'] as String?;
          if (storedStatus != null) {
            membershipStatus = storedStatus;
            print("ContactsBloc: Using stored membership status: $membershipStatus for ${contact.userId}");
          }
        }
        
        // If no stored status, fall back to Matrix room status
        if (membershipStatus == null) {
          membershipStatus = await roomService.getUserRoomMembership(directRoomId, contact.userId);
          print("ContactsBloc: Contact ${contact.userId} has Matrix membership status: $membershipStatus in room $directRoomId");
        }
      } else {
        print("ContactsBloc: No direct room found for contact ${contact.userId}");
      }
      
      contactDisplays.add(ContactDisplay(
        userId: contact.userId,
        displayName: contact.displayName ?? 'Deleted User',
        avatarUrl: contact.avatarUrl,
        lastSeen: 'Offline',
        membershipStatus: membershipStatus,
      ));
    }
    
    print("ContactsBloc: Loaded ${contactDisplays.length} contacts");
    return contactDisplays;
  }

  // Handle new contact invitation immediately (similar to GroupsBloc.handleNewMemberInvited)
  Future<void> handleNewContactInvited(String roomId, String userId) async {
    try {
      print("ContactsBloc: Handling new contact invite for $userId in room $roomId");

      // Get user profile and insert/update user
      final profileInfo = await roomService.client.getUserProfile(userId);
      final newUser = GridUser(
        userId: userId,
        displayName: profileInfo.displayname,
        avatarUrl: profileInfo.avatarUrl?.toString(),
        lastSeen: DateTime.now().toIso8601String(),
        profileStatus: "",
      );
      await userRepository.insertUser(newUser);

      // Insert direct relationship with invite status
      await userRepository.insertUserRelationship(
        userId,
        roomId,
        true, // isDirect
        membershipStatus: 'invite', // Store invite status explicitly
      );

      // Force refresh contacts to show the new contact immediately
      add(RefreshContacts());
      
      print("ContactsBloc: New contact invite handled successfully");
    } catch (e) {
      print("ContactsBloc: Error handling new contact invite: $e");
    }
  }
}