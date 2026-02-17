import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_event.dart';
import 'package:grid_frontend/blocs/groups/groups_state.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/models/grid_user.dart';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:matrix/matrix.dart' as matrix;

// Mock classes
class MockRoomService extends Mock implements RoomService {}
class MockRoomRepository extends Mock implements RoomRepository {}
class MockUserRepository extends Mock implements UserRepository {}
class MockLocationRepository extends Mock implements LocationRepository {}
class MockUserLocationProvider extends Mock implements UserLocationProvider {}
class MockMapBloc extends Mock implements MapBloc {}
class MockMatrixClient extends Mock implements matrix.Client {}

// Fake classes for fallback values
class FakeMapEvent extends Fake implements MapEvent {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeMapEvent());
  });

  group('GroupsBloc', () {
    late GroupsBloc bloc;
    late MockRoomService mockRoomService;
    late MockRoomRepository mockRoomRepository;
    late MockUserRepository mockUserRepository;
    late MockLocationRepository mockLocationRepository;
    late MockUserLocationProvider mockUserLocationProvider;
    late MockMapBloc mockMapBloc;
    late MockMatrixClient mockMatrixClient;

    setUp(() {
      mockRoomService = MockRoomService();
      mockRoomRepository = MockRoomRepository();
      mockUserRepository = MockUserRepository();
      mockLocationRepository = MockLocationRepository();
      mockUserLocationProvider = MockUserLocationProvider();
      mockMapBloc = MockMapBloc();
      mockMatrixClient = MockMatrixClient();

      when(() => mockRoomService.client).thenReturn(mockMatrixClient);

      bloc = GroupsBloc(
        roomService: mockRoomService,
        roomRepository: mockRoomRepository,
        userRepository: mockUserRepository,
        locationRepository: mockLocationRepository,
        userLocationProvider: mockUserLocationProvider,
        mapBloc: mockMapBloc,
      );
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is GroupsInitial', () {
      expect(bloc.state, isA<GroupsInitial>());
    });

    group('LoadGroups', () {
      final mockRooms = [
        Room(
          roomId: 'room1',
          name: 'Group 1',
          isGroup: true,
          lastActivity: '2024-01-01T00:00:00Z',
          members: ['user1', 'user2'],
          expirationTimestamp: 0,
        ),
        Room(
          roomId: 'room2',
          name: 'Group 2',
          isGroup: true,
          lastActivity: '2024-01-02T00:00:00Z',
          members: ['user1', 'user3'],
          expirationTimestamp: 0,
        ),
      ];

      blocTest<GroupsBloc, GroupsState>(
        'emits [GroupsLoading, GroupsLoaded] when loading groups succeeds',
        build: () {
          when(() => mockRoomRepository.getNonExpiredRooms())
              .thenAnswer((_) async => mockRooms);
          return bloc;
        },
        act: (bloc) => bloc.add(LoadGroups()),
        expect: () => [
          isA<GroupsLoading>(),
          isA<GroupsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as GroupsLoaded;
          expect(state.groups.length, equals(2));
          // Should be sorted by lastActivity descending
          expect(state.groups.first.name, equals('Group 2')); // More recent
        },
      );

      blocTest<GroupsBloc, GroupsState>(
        'filters expired rooms',
        build: () {
          final roomsWithExpired = [
            Room(
              roomId: 'room1',
              name: 'Active Group',
              isGroup: true,
              lastActivity: '2024-01-01T00:00:00Z',
              members: ['user1'],
              expirationTimestamp: 0, // Never expires
            ),
            // Room repository should filter expired rooms
          ];
          when(() => mockRoomRepository.getNonExpiredRooms())
              .thenAnswer((_) async => roomsWithExpired);
          return bloc;
        },
        act: (bloc) => bloc.add(LoadGroups()),
        expect: () => [
          isA<GroupsLoading>(),
          isA<GroupsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as GroupsLoaded;
          expect(state.groups.length, equals(1));
          expect(state.groups.first.name, equals('Active Group'));
        },
      );

      blocTest<GroupsBloc, GroupsState>(
        'emits [GroupsLoading, GroupsError] when loading groups fails',
        build: () {
          when(() => mockRoomRepository.getNonExpiredRooms())
              .thenThrow(Exception('Database error'));
          return bloc;
        },
        act: (bloc) => bloc.add(LoadGroups()),
        expect: () => [
          isA<GroupsLoading>(),
          isA<GroupsError>(),
        ],
        verify: (bloc) {
          final state = bloc.state as GroupsError;
          expect(state.message, contains('Database error'));
        },
      );
    });

    group('RefreshGroups', () {
      final mockRooms = [
        Room(
          roomId: 'room1',
          name: 'Updated Group',
          isGroup: true,
          lastActivity: '2024-01-01T00:00:00Z',
          members: ['user1', 'user2'],
          expirationTimestamp: 0,
        ),
      ];

      blocTest<GroupsBloc, GroupsState>(
        'emits [GroupsLoaded] with updated groups',
        build: () {
          when(() => mockRoomRepository.getNonExpiredRooms())
              .thenAnswer((_) async => mockRooms);
          return bloc;
        },
        act: (bloc) => bloc.add(RefreshGroups()),
        expect: () => [
          isA<GroupsLoading>(),
          isA<GroupsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as GroupsLoaded;
          expect(state.groups.length, equals(1));
          expect(state.groups.first.name, equals('Updated Group'));
        },
      );
    });

    group('SearchGroups', () {
      final mockRooms = [
        Room(
          roomId: 'room1',
          name: 'Flutter Group',
          isGroup: true,
          lastActivity: '2024-01-01T00:00:00Z',
          members: ['user1'],
          expirationTimestamp: 0,
        ),
        Room(
          roomId: 'room2',
          name: 'Dart Developers',
          isGroup: true,
          lastActivity: '2024-01-02T00:00:00Z',
          members: ['user2'],
          expirationTimestamp: 0,
        ),
      ];

      blocTest<GroupsBloc, GroupsState>(
        'filters groups by name',
        build: () {
          when(() => mockRoomRepository.getNonExpiredRooms())
              .thenAnswer((_) async => mockRooms);
          return bloc;
        },
        act: (bloc) {
          bloc.add(LoadGroups());
          bloc.add(const SearchGroups('Flutter'));
        },
        expect: () => [
          isA<GroupsLoading>(),
          isA<GroupsLoaded>(), // After LoadGroups
          isA<GroupsLoaded>(), // After SearchGroups
        ],
        verify: (bloc) {
          final state = bloc.state as GroupsLoaded;
          expect(state.groups.length, equals(1));
          expect(state.groups.first.name, contains('Flutter'));
        },
      );

      test('returns full list when query is empty', () async {
        // Setup mocks
        when(() => mockRoomRepository.getNonExpiredRooms())
            .thenAnswer((_) async => mockRooms);

        // Load groups first
        bloc.add(LoadGroups());
        await Future.delayed(const Duration(milliseconds: 50));

        // Ensure groups are loaded
        expect(bloc.state, isA<GroupsLoaded>());
        final loadedState = bloc.state as GroupsLoaded;
        expect(loadedState.groups.length, equals(2));

        // Search with empty query
        bloc.add(const SearchGroups(''));
        await Future.delayed(const Duration(milliseconds: 10));

        // Verify result
        final finalState = bloc.state as GroupsLoaded;
        expect(finalState.groups.length, equals(2));
      });
    });

    group('DeleteGroup', () {
      final mockRoom = Room(
        roomId: 'room1',
        name: 'Test Group',
        isGroup: true,
        lastActivity: '2024-01-01T00:00:00Z',
        members: ['user1', 'user2'],
        expirationTimestamp: 0,
      );

      blocTest<GroupsBloc, GroupsState>(
        'deletes group and removes members from map if they have no other rooms',
        build: () {
          when(() => mockRoomRepository.getRoomById('room1'))
              .thenAnswer((_) async => mockRoom);
          when(() => mockRoomService.leaveRoom('room1'))
              .thenAnswer((_) async => true);
          when(() => mockRoomRepository.deleteRoom('room1'))
              .thenAnswer((_) async {});
          when(() => mockRoomRepository.getUserRooms('user1'))
              .thenAnswer((_) async => []); // No other rooms
          when(() => mockRoomRepository.getUserRooms('user2'))
              .thenAnswer((_) async => ['other_room']); // Has other rooms
          when(() => mockMapBloc.add(any())).thenReturn(null);
          when(() => mockRoomRepository.getNonExpiredRooms())
              .thenAnswer((_) async => []); // After deletion
          return bloc;
        },
        act: (bloc) => bloc.add(const DeleteGroup('room1')),
        expect: () => [
          isA<GroupsLoaded>(),
        ],
        verify: (bloc) {
          verify(() => mockRoomService.leaveRoom('room1')).called(1);
          verify(() => mockRoomRepository.deleteRoom('room1')).called(1);
          verify(() => mockMapBloc.add(any())).called(1); // Only for user1
        },
      );
    });

    group('LoadGroupMembers', () {
      final mockRoom = Room(
        roomId: 'room1',
        name: 'Test Group',
        isGroup: true,
        lastActivity: '2024-01-01T00:00:00Z',
        members: ['user1', 'user2'],
        expirationTimestamp: 0,
      );

      final mockUsers = [
        GridUser(
          userId: 'user1',
          displayName: 'User 1',
          lastSeen: '2024-01-01T00:00:00Z',
        ),
        GridUser(
          userId: 'user2',
          displayName: 'User 2',
          lastSeen: '2024-01-01T00:00:00Z',
        ),
      ];

      blocTest<GroupsBloc, GroupsState>(
        'loads group members with membership statuses',
        build: () {
          when(() => mockRoomRepository.getRoomById('room1'))
              .thenAnswer((_) async => mockRoom);
          when(() => mockUserRepository.getUserRelationshipsForRoom('room1'))
              .thenAnswer((_) async => [
            {'userId': 'user1', 'membershipStatus': 'join'},
            {'userId': 'user2', 'membershipStatus': 'join'},
          ]);
          when(() => mockUserRepository.getGroupParticipants())
              .thenAnswer((_) async => mockUsers);
          when(() => mockRoomService.getUserRoomMembership('room1', 'user1'))
              .thenAnswer((_) async => 'join');
          when(() => mockRoomService.getUserRoomMembership('room1', 'user2'))
              .thenAnswer((_) async => 'join');
          when(() => mockUserRepository.updateMembershipStatus(any(), any(), any()))
              .thenAnswer((_) async {});
          return bloc;
        },
        seed: () => GroupsLoaded([mockRoom]), // Provide initial state with groups
        act: (bloc) => bloc.add(const LoadGroupMembers('room1')),
        expect: () => [
          isA<GroupsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as GroupsLoaded;
          expect(state.selectedRoomId, equals('room1'));
          expect(state.selectedRoomMembers?.length, equals(2));
          expect(state.membershipStatuses?['user1'], equals('join'));
          expect(state.membershipStatuses?['user2'], equals('join'));
        },
      );
    });

    group('UpdateMemberStatus', () {
      final initialState = GroupsLoaded(
        [Room(
          roomId: 'room1',
          name: 'Test Group',
          isGroup: true,
          lastActivity: '2024-01-01T00:00:00Z',
          members: ['user1', 'user2'],
          expirationTimestamp: 0,
        )],
        selectedRoomId: 'room1',
        selectedRoomMembers: [
          GridUser(userId: 'user1', displayName: 'User 1', lastSeen: '2024-01-01T00:00:00Z'),
        ],
        membershipStatuses: {'user1': 'invite'},
      );

      blocTest<GroupsBloc, GroupsState>(
        'updates member status when user joins',
        build: () {
          when(() => mockRoomRepository.getRoomById('room1'))
              .thenAnswer((_) async => initialState.groups.first);
          when(() => mockUserRepository.getGroupParticipants())
              .thenAnswer((_) async => [
            GridUser(userId: 'user1', displayName: 'User 1', lastSeen: '2024-01-01T00:00:00Z'),
          ]);
          return bloc;
        },
        seed: () => initialState,
        act: (bloc) => bloc.add(UpdateMemberStatus('room1', 'user1', 'join')),
        expect: () => [
          isA<GroupsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as GroupsLoaded;
          expect(state.membershipStatuses?['user1'], equals('join'));
        },
      );
    });

    group('Error Handling', () {
      blocTest<GroupsBloc, GroupsState>(
        'emits GroupsError when LoadGroups fails',
        build: () {
          when(() => mockRoomRepository.getNonExpiredRooms())
              .thenThrow(Exception('Network error'));
          return bloc;
        },
        act: (bloc) => bloc.add(LoadGroups()),
        expect: () => [
          isA<GroupsLoading>(),
          isA<GroupsError>(),
        ],
        verify: (bloc) {
          final state = bloc.state as GroupsError;
          expect(state.message, contains('Network error'));
        },
      );

      blocTest<GroupsBloc, GroupsState>(
        'emits GroupsError when RefreshGroups fails',
        build: () {
          when(() => mockRoomRepository.getNonExpiredRooms())
              .thenThrow(Exception('Refresh error'));
          return bloc;
        },
        act: (bloc) => bloc.add(RefreshGroups()),
        expect: () => [
          isA<GroupsError>(),
        ],
        verify: (bloc) {
          final state = bloc.state as GroupsError;
          expect(state.message, contains('Refresh error'));
        },
      );
    });

    group('Edge Cases', () {
      blocTest<GroupsBloc, GroupsState>(
        'handles deleted users in member list',
        build: () {
          final deletedUser = GridUser(
            userId: 'deleted_user',
            displayName: '', // Empty name indicates deleted user
            lastSeen: '2024-01-01T00:00:00Z',
          );

          final testRoom = Room(
            roomId: 'room1',
            name: 'Test Group',
            isGroup: true,
            lastActivity: '2024-01-01T00:00:00Z',
            members: ['deleted_user'],
            expirationTimestamp: 0,
          );

          when(() => mockRoomRepository.getRoomById('room1'))
              .thenAnswer((_) async => testRoom);
          when(() => mockUserRepository.getUserRelationshipsForRoom('room1'))
              .thenAnswer((_) async => [
            {'userId': 'deleted_user', 'membershipStatus': 'join'},
          ]);
          when(() => mockUserRepository.getGroupParticipants())
              .thenAnswer((_) async => [deletedUser]);
          when(() => mockRoomService.getUserRoomMembership('room1', 'deleted_user'))
              .thenAnswer((_) async => 'join');
          when(() => mockUserRepository.updateMembershipStatus(any(), any(), any()))
              .thenAnswer((_) async {});
          return bloc;
        },
        seed: () => GroupsLoaded([Room(
          roomId: 'room1',
          name: 'Test Group',
          isGroup: true,
          lastActivity: '2024-01-01T00:00:00Z',
          members: ['deleted_user'],
          expirationTimestamp: 0,
        )]),
        act: (bloc) => bloc.add(const LoadGroupMembers('room1')),
        expect: () => [
          isA<GroupsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as GroupsLoaded;
          expect(state.selectedRoomMembers?.first.displayName, equals('Deleted User'));
        },
      );

      test('does not update when room is not found', () async {
        when(() => mockRoomRepository.getRoomById('nonexistent'))
            .thenAnswer((_) async => null);

        bloc.add(const LoadGroupMembers('nonexistent'));
        await Future.delayed(const Duration(milliseconds: 10));

        expect(bloc.state, isA<GroupsInitial>());
      });
    });
  });
}