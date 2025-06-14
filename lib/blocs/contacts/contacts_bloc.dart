import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';
import 'package:grid_frontend/blocs/contacts/contacts_state.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/models/grid_user.dart';
import 'package:grid_frontend/services/others_profile_service.dart';
import 'package:grid_frontend/services/logger_service.dart';

import '../../providers/user_location_provider.dart';
import '../map/map_event.dart';

class ContactsBloc extends Bloc<ContactsEvent, ContactsState> {
  static const String _tag = 'ContactsBloc';
  
  final RoomService roomService;
  final UserRepository userRepository;
  final RoomRepository roomRepository;
  final LocationRepository locationRepository;
  List<ContactDisplay> _allContacts = []; // Cache for search filtering
  final MapBloc mapBloc;
  final UserLocationProvider userLocationProvider;
  final SharingPreferencesRepository sharingPreferencesRepository;
  final OthersProfileService _othersProfileService = OthersProfileService();

  ContactsBloc({
    required this.roomService,
    required this.userRepository,
    required this.roomRepository,
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
    emit(ContactsLoading());
    try {
      _allContacts = await _loadContacts();
      emit(ContactsLoaded(_allContacts));
    } catch (e) {
      emit(ContactsError(e.toString()));
    }
  }

  Future<void> _onRefreshContacts(RefreshContacts event, Emitter<ContactsState> emit) async {
    try {
      final updatedContacts = await _loadContacts();
      _allContacts = updatedContacts; // Update the cache
      
      // Only log if contact count changed
      if (state is ContactsLoaded && (state as ContactsLoaded).contacts.length != updatedContacts.length) {
        Logger.info(_tag, 'Contacts updated', data: {'count': updatedContacts.length});
      }
      
      emit(ContactsLoaded(_allContacts)); // Equatable will handle equality
    } catch (e) {
      Logger.error(_tag, 'Failed to refresh contacts', error: e);
      emit(ContactsError(e.toString()));
    }
  }


  Future<void> _onDeleteContact(DeleteContact event, Emitter<ContactsState> emit) async {
    try {
      Logger.info(_tag, 'Deleting contact', data: {'userId': event.userId});
      final roomId = await userRepository.getDirectRoomForContact(event.userId);
      
      if (roomId != null) {
        await roomService.leaveRoom(roomId);
        await userRepository.removeContact(event.userId);
        final wasDeleted = await locationRepository.deleteUserLocationsIfNotInRooms(event.userId);
        if (wasDeleted) {
          userLocationProvider.removeUserLocation(event.userId);
          mapBloc.add(RemoveUserLocation(event.userId));
        }
        await sharingPreferencesRepository.deleteSharingPreferences(event.userId, 'user');
        
        // Check if user is in any groups with us
        final userRooms = await roomRepository.getUserRooms(event.userId);
        final groupRooms = <String>[];
        
        for (final roomId in userRooms) {
          final room = await roomRepository.getRoomById(roomId);
          if (room != null && room.isGroup) {
            groupRooms.add(roomId);
          }
        }
        
        // If user is not in any groups with us, clear their cached profile picture
        if (groupRooms.isEmpty) {
          Logger.debug(_tag, 'Clearing cached profile picture', data: {'userId': event.userId});
          await _othersProfileService.clearUserProfile(event.userId);
        }
        
        // Reload contacts and update cache
        _allContacts = await _loadContacts();
        Logger.info(_tag, 'Contact deleted successfully', data: {
          'userId': event.userId,
          'remainingContacts': _allContacts.length
        });
        
        // Force emit with new list to ensure UI updates
        emit(ContactsLoaded(_allContacts));
      } else {
        Logger.warning(_tag, 'No room found for contact deletion', data: {'userId': event.userId});
      }
    } catch (e) {
      Logger.error(_tag, 'Failed to delete contact', error: e, data: {'userId': event.userId});
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
            Logger.debug(_tag, 'Using stored membership status', data: {
              'status': membershipStatus,
              'userId': contact.userId
            });
          }
        }
        
        // If no stored status, fall back to Matrix room status
        if (membershipStatus == null) {
          membershipStatus = await roomService.getUserRoomMembership(directRoomId, contact.userId);
          Logger.debug(_tag, 'Matrix membership status', data: {
            'userId': contact.userId,
            'status': membershipStatus,
            'roomId': directRoomId
          });
        }
      } else {
        Logger.debug(_tag, 'No direct room found', data: {'userId': contact.userId});
      }
      
      contactDisplays.add(ContactDisplay(
        userId: contact.userId,
        displayName: contact.displayName ?? 'Deleted User',
        avatarUrl: contact.avatarUrl,
        lastSeen: 'Offline',
        membershipStatus: membershipStatus,
      ));
    }
    
    Logger.debug(_tag, 'Contacts loaded', data: {'count': contactDisplays.length});
    return contactDisplays;
  }

  // Handle new contact invitation immediately (similar to GroupsBloc.handleNewMemberInvited)
  Future<void> handleNewContactInvited(String roomId, String userId) async {
    try {
      Logger.info(_tag, 'New contact invite', data: {
        'userId': userId,
        'roomId': roomId
      });

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
    } catch (e) {
      Logger.error(_tag, 'Failed to handle contact invite', error: e, data: {
        'userId': userId,
        'roomId': roomId
      });
    }
  }
}