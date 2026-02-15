import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_event.dart';
import 'package:grid_frontend/blocs/contacts/contacts_state.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/models/contact_display.dart';
import 'package:grid_frontend/models/grid_user.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';

// Mock classes
class MockRoomService extends Mock implements RoomService {}
class MockUserRepository extends Mock implements UserRepository {}
class MockLocationRepository extends Mock implements LocationRepository {}
class MockMapBloc extends Mock implements MapBloc {}
class MockUserLocationProvider extends Mock implements UserLocationProvider {}
class MockSharingPreferencesRepository extends Mock implements SharingPreferencesRepository {}

void main() {
  group('ContactsBloc', () {
    late ContactsBloc bloc;
    late MockRoomService mockRoomService;
    late MockUserRepository mockUserRepository;
    late MockLocationRepository mockLocationRepository;
    late MockMapBloc mockMapBloc;
    late MockUserLocationProvider mockUserLocationProvider;
    late MockSharingPreferencesRepository mockSharingPreferencesRepository;

    setUp(() {
      mockRoomService = MockRoomService();
      mockUserRepository = MockUserRepository();
      mockLocationRepository = MockLocationRepository();
      mockMapBloc = MockMapBloc();
      mockUserLocationProvider = MockUserLocationProvider();
      mockSharingPreferencesRepository = MockSharingPreferencesRepository();

      bloc = ContactsBloc(
        roomService: mockRoomService,
        userRepository: mockUserRepository,
        locationRepository: mockLocationRepository,
        mapBloc: mockMapBloc,
        userLocationProvider: mockUserLocationProvider,
        sharingPreferencesRepository: mockSharingPreferencesRepository,
      );

      // Common setup
      when(() => mockRoomService.getMyUserId()).thenReturn('current_user_id');
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is ContactsInitial', () {
      expect(bloc.state, isA<ContactsInitial>());
    });

    group('LoadContacts', () {
      final mockContacts = [
        GridUser(userId: 'user1', displayName: 'User 1', lastSeen: '2024-01-01T00:00:00Z'),
        GridUser(userId: 'user2', displayName: 'User 2', lastSeen: '2024-01-01T00:00:00Z'),
      ];

      blocTest<ContactsBloc, ContactsState>(
        'emits [ContactsLoading, ContactsLoaded] on first load',
        build: () {
          when(() => mockUserRepository.getDirectContacts())
              .thenAnswer((_) async => mockContacts);
          when(() => mockUserRepository.getDirectRoomForContact(any()))
              .thenAnswer((_) async => 'room1');
          when(() => mockUserRepository.getUserRelationshipsForRoom(any()))
              .thenAnswer((_) async => []);
          when(() => mockRoomService.getUserRoomMembership(any(), any()))
              .thenAnswer((_) async => 'join');
          return bloc;
        },
        act: (bloc) => bloc.add(LoadContacts()),
        expect: () => [
          isA<ContactsLoading>(),
          isA<ContactsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as ContactsLoaded;
          expect(state.contacts.length, equals(2));
          expect(state.contacts.first.userId, equals('user1'));
          expect(state.contacts.first.displayName, equals('User 1'));
        },
      );

      blocTest<ContactsBloc, ContactsState>(
        'emits [ContactsLoaded] when contacts already exist (no Loading state shown)',
        build: () {
          // Pre-populate contacts to simulate existing contacts
          when(() => mockUserRepository.getDirectContacts())
              .thenAnswer((_) async => mockContacts);
          when(() => mockUserRepository.getDirectRoomForContact(any()))
              .thenAnswer((_) async => 'room1');
          when(() => mockUserRepository.getUserRelationshipsForRoom(any()))
              .thenAnswer((_) async => []);
          when(() => mockRoomService.getUserRoomMembership(any(), any()))
              .thenAnswer((_) async => 'join');
          
          // Simulate that contacts were already loaded
          bloc.add(LoadContacts());
          return bloc;
        },
        act: (bloc) => bloc.add(LoadContacts()),
        skip: 2, // Skip the initial loading states
        expect: () => [
          isA<ContactsLoaded>(),
        ],
      );

      blocTest<ContactsBloc, ContactsState>(
        'emits [ContactsLoading, ContactsLoaded([])] when no contacts exist',
        build: () {
          when(() => mockUserRepository.getDirectContacts())
              .thenAnswer((_) async => []);
          return bloc;
        },
        act: (bloc) => bloc.add(LoadContacts()),
        expect: () => [
          isA<ContactsLoading>(),
          isA<ContactsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as ContactsLoaded;
          expect(state.contacts, isEmpty);
        },
      );

      blocTest<ContactsBloc, ContactsState>(
        'emits [ContactsLoading, ContactsError] when loading contacts fails',
        build: () {
          when(() => mockUserRepository.getDirectContacts())
              .thenThrow(Exception('Database error'));
          return bloc;
        },
        act: (bloc) => bloc.add(LoadContacts()),
        expect: () => [
          isA<ContactsLoading>(),
          isA<ContactsError>(),
        ],
        verify: (bloc) {
          final state = bloc.state as ContactsError;
          expect(state.message, contains('Database error'));
        },
      );
    });

    group('RefreshContacts', () {
      final mockContacts = [
        GridUser(userId: 'user1', displayName: 'User 1', lastSeen: '2024-01-01T00:00:00Z'),
        GridUser(userId: 'user2', displayName: 'User 2', lastSeen: '2024-01-01T00:00:00Z'),
      ];

      blocTest<ContactsBloc, ContactsState>(
        'emits [ContactsLoaded] with updated list',
        build: () {
          when(() => mockUserRepository.getDirectContacts())
              .thenAnswer((_) async => mockContacts);
          when(() => mockUserRepository.getDirectRoomForContact(any()))
              .thenAnswer((_) async => 'room1');
          when(() => mockUserRepository.getUserRelationshipsForRoom(any()))
              .thenAnswer((_) async => []);
          when(() => mockRoomService.getUserRoomMembership(any(), any()))
              .thenAnswer((_) async => 'join');
          return bloc;
        },
        act: (bloc) => bloc.add(RefreshContacts()),
        expect: () => [
          isA<ContactsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as ContactsLoaded;
          expect(state.contacts.length, equals(2));
        },
      );
    });

    group('SearchContacts', () {
      final mockContacts = [
        ContactDisplay(userId: 'alice123', displayName: 'Alice Smith', lastSeen: 'Offline'),
        ContactDisplay(userId: 'bob456', displayName: 'Bob Johnson', lastSeen: 'Offline'),
        ContactDisplay(userId: 'charlie789', displayName: 'Charlie Brown', lastSeen: 'Offline'),
      ];

      blocTest<ContactsBloc, ContactsState>(
        'emits filtered list with matching query',
        build: () {
          // Set up initial loaded state with contacts
          when(() => mockUserRepository.getDirectContacts()).thenAnswer((_) async => [
            GridUser(userId: 'alice123', displayName: 'Alice Smith', lastSeen: '2024-01-01T00:00:00Z'),
            GridUser(userId: 'bob456', displayName: 'Bob Johnson', lastSeen: '2024-01-01T00:00:00Z'),
            GridUser(userId: 'charlie789', displayName: 'Charlie Brown', lastSeen: '2024-01-01T00:00:00Z'),
          ]);
          when(() => mockUserRepository.getDirectRoomForContact(any())).thenAnswer((_) async => 'room1');
          when(() => mockUserRepository.getUserRelationshipsForRoom(any())).thenAnswer((_) async => []);
          when(() => mockRoomService.getUserRoomMembership(any(), any())).thenAnswer((_) async => 'join');
          return bloc;
        },
        act: (bloc) {
          bloc.add(LoadContacts()); // Load contacts first
          bloc.add(SearchContacts('alice'));
        },
        skip: 2, // Skip loading states
        expect: () => [
          isA<ContactsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as ContactsLoaded;
          expect(state.contacts.length, equals(1));
          expect(state.contacts.first.displayName, contains('Alice'));
        },
      );

      blocTest<ContactsBloc, ContactsState>(
        'emits full list when query is empty',
        build: () {
          when(() => mockUserRepository.getDirectContacts()).thenAnswer((_) async => [
            GridUser(userId: 'alice123', displayName: 'Alice Smith', lastSeen: '2024-01-01T00:00:00Z'),
            GridUser(userId: 'bob456', displayName: 'Bob Johnson', lastSeen: '2024-01-01T00:00:00Z'),
          ]);
          when(() => mockUserRepository.getDirectRoomForContact(any())).thenAnswer((_) async => 'room1');
          when(() => mockUserRepository.getUserRelationshipsForRoom(any())).thenAnswer((_) async => []);
          when(() => mockRoomService.getUserRoomMembership(any(), any())).thenAnswer((_) async => 'join');
          return bloc;
        },
        act: (bloc) {
          bloc.add(LoadContacts());
          bloc.add(SearchContacts(''));
        },
        skip: 2, // Skip loading states
        expect: () => [
          isA<ContactsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as ContactsLoaded;
          expect(state.contacts.length, equals(2));
        },
      );

      blocTest<ContactsBloc, ContactsState>(
        'search is case insensitive',
        build: () {
          when(() => mockUserRepository.getDirectContacts()).thenAnswer((_) async => [
            GridUser(userId: 'alice123', displayName: 'Alice Smith', lastSeen: '2024-01-01T00:00:00Z'),
          ]);
          when(() => mockUserRepository.getDirectRoomForContact(any())).thenAnswer((_) async => 'room1');
          when(() => mockUserRepository.getUserRelationshipsForRoom(any())).thenAnswer((_) async => []);
          when(() => mockRoomService.getUserRoomMembership(any(), any())).thenAnswer((_) async => 'join');
          return bloc;
        },
        act: (bloc) {
          bloc.add(LoadContacts());
          bloc.add(SearchContacts('ALICE'));
        },
        skip: 2, // Skip loading states
        expect: () => [
          isA<ContactsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as ContactsLoaded;
          expect(state.contacts.length, equals(1));
          expect(state.contacts.first.displayName, equals('Alice Smith'));
        },
      );
    });

    group('DeleteContact', () {
      blocTest<ContactsBloc, ContactsState>(
        'removes contact from list and leaves room',
        build: () {
          when(() => mockUserRepository.getDirectRoomForContact('user1'))
              .thenAnswer((_) async => 'room1');
          when(() => mockUserRepository.getUserRooms('user1'))
              .thenAnswer((_) async => ['room1']); // Only in direct room
          when(() => mockRoomService.leaveRoom('room1')).thenAnswer((_) async => true);
          when(() => mockUserRepository.removeContact('user1')).thenAnswer((_) async {});
          when(() => mockLocationRepository.deleteUserLocationsIfNotInRooms('user1'))
              .thenAnswer((_) async => true);
          when(() => mockUserLocationProvider.removeUserLocation('user1')).thenReturn(null);
          when(() => mockMapBloc.add(any())).thenReturn(null);
          when(() => mockSharingPreferencesRepository.deleteSharingPreferences('user1', 'user'))
              .thenAnswer((_) async {});
          
          // Setup for the reload after deletion
          when(() => mockUserRepository.getDirectContacts()).thenAnswer((_) async => [
            GridUser(userId: 'user2', displayName: 'User 2', lastSeen: '2024-01-01T00:00:00Z'),
          ]);
          when(() => mockUserRepository.getDirectRoomForContact('user2'))
              .thenAnswer((_) async => 'room2');
          when(() => mockUserRepository.getUserRelationshipsForRoom('room2'))
              .thenAnswer((_) async => []);
          when(() => mockRoomService.getUserRoomMembership('room2', 'user2'))
              .thenAnswer((_) async => 'join');
          
          return bloc;
        },
        act: (bloc) => bloc.add(DeleteContact('user1')),
        expect: () => [
          isA<ContactsLoaded>(),
        ],
        verify: (bloc) {
          verify(() => mockRoomService.leaveRoom('room1')).called(1);
          verify(() => mockUserRepository.removeContact('user1')).called(1);
          verify(() => mockLocationRepository.deleteUserLocationsIfNotInRooms('user1')).called(1);
          verify(() => mockUserLocationProvider.removeUserLocation('user1')).called(1);
          verify(() => mockSharingPreferencesRepository.deleteSharingPreferences('user1', 'user')).called(1);
        },
      );

      blocTest<ContactsBloc, ContactsState>(
        'removes contact but keeps on map when user is in groups',
        build: () {
          when(() => mockUserRepository.getDirectRoomForContact('user1'))
              .thenAnswer((_) async => 'room1');
          when(() => mockUserRepository.getUserRooms('user1'))
              .thenAnswer((_) async => ['room1', 'group_room1']); // In direct + group room
          when(() => mockRoomService.leaveRoom('room1')).thenAnswer((_) async => true);
          when(() => mockUserRepository.removeContact('user1')).thenAnswer((_) async {});
          when(() => mockSharingPreferencesRepository.deleteSharingPreferences('user1', 'user'))
              .thenAnswer((_) async {});
          
          // Setup for the reload after deletion
          when(() => mockUserRepository.getDirectContacts()).thenAnswer((_) async => []);
          
          return bloc;
        },
        act: (bloc) => bloc.add(DeleteContact('user1')),
        expect: () => [
          isA<ContactsLoaded>(),
        ],
        verify: (bloc) {
          verify(() => mockRoomService.leaveRoom('room1')).called(1);
          verify(() => mockUserRepository.removeContact('user1')).called(1);
          // These should NOT be called because user is in groups
          verifyNever(() => mockLocationRepository.deleteUserLocationsIfNotInRooms('user1'));
          verifyNever(() => mockUserLocationProvider.removeUserLocation('user1'));
          verify(() => mockSharingPreferencesRepository.deleteSharingPreferences('user1', 'user')).called(1);
        },
      );

      blocTest<ContactsBloc, ContactsState>(
        'removes contact but does not remove from map when user is not in groups',
        build: () {
          when(() => mockUserRepository.getDirectRoomForContact('user1'))
              .thenAnswer((_) async => 'room1');
          when(() => mockUserRepository.getUserRooms('user1'))
              .thenAnswer((_) async => ['room1']); // Only in direct room
          when(() => mockRoomService.leaveRoom('room1')).thenAnswer((_) async => true);
          when(() => mockUserRepository.removeContact('user1')).thenAnswer((_) async {});
          when(() => mockLocationRepository.deleteUserLocationsIfNotInRooms('user1'))
              .thenAnswer((_) async => false); // No locations were deleted
          when(() => mockSharingPreferencesRepository.deleteSharingPreferences('user1', 'user'))
              .thenAnswer((_) async {});
          
          // Setup for the reload after deletion
          when(() => mockUserRepository.getDirectContacts()).thenAnswer((_) async => []);
          
          return bloc;
        },
        act: (bloc) => bloc.add(DeleteContact('user1')),
        expect: () => [
          isA<ContactsLoaded>(),
        ],
        verify: (bloc) {
          verify(() => mockLocationRepository.deleteUserLocationsIfNotInRooms('user1')).called(1);
          // These should NOT be called because no locations were deleted
          verifyNever(() => mockUserLocationProvider.removeUserLocation('user1'));
          verifyNever(() => mockMapBloc.add(any()));
        },
      );
    });

    group('Error Handling', () {
      blocTest<ContactsBloc, ContactsState>(
        'emits ContactsError when RefreshContacts fails',
        build: () {
          when(() => mockUserRepository.getDirectContacts())
              .thenThrow(Exception('Network error'));
          return bloc;
        },
        act: (bloc) => bloc.add(RefreshContacts()),
        expect: () => [
          isA<ContactsError>(),
        ],
        verify: (bloc) {
          final state = bloc.state as ContactsError;
          expect(state.message, contains('Network error'));
        },
      );

      blocTest<ContactsBloc, ContactsState>(
        'emits ContactsError when DeleteContact fails',
        build: () {
          when(() => mockUserRepository.getDirectRoomForContact('user1'))
              .thenThrow(Exception('Delete error'));
          return bloc;
        },
        act: (bloc) => bloc.add(DeleteContact('user1')),
        expect: () => [
          isA<ContactsError>(),
        ],
        verify: (bloc) {
          final state = bloc.state as ContactsError;
          expect(state.message, contains('Delete error'));
        },
      );
    });
  });
}