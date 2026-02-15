import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:grid_frontend/blocs/invitations/invitations_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_event.dart';
import 'package:grid_frontend/blocs/invitations/invitations_state.dart';
import 'package:grid_frontend/repositories/invitations_repository.dart';

class MockInvitationsRepository extends Mock implements InvitationsRepository {}

void main() {
  group('InvitationsBloc', () {
    late InvitationsBloc bloc;
    late MockInvitationsRepository mockRepository;

    setUp(() {
      mockRepository = MockInvitationsRepository();
      bloc = InvitationsBloc(repository: mockRepository);
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is InvitationsInitial', () {
      expect(bloc.state, isA<InvitationsInitial>());
    });

    group('LoadInvitations', () {
      final mockInvitations = [
        {'roomId': 'room1', 'inviter': 'user1', 'roomName': 'Test Room 1'},
        {'roomId': 'room2', 'inviter': 'user2', 'roomName': 'Test Room 2'},
      ];

      blocTest<InvitationsBloc, InvitationsState>(
        'emits [InvitationsLoading, InvitationsLoaded] when loadInvitations succeeds',
        build: () {
          when(() => mockRepository.loadInvitations())
              .thenAnswer((_) async => mockInvitations);
          return bloc;
        },
        act: (bloc) => bloc.add(LoadInvitations()),
        expect: () => [
          isA<InvitationsLoading>(),
          isA<InvitationsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsLoaded;
          expect(state.invitations, equals(mockInvitations));
        },
      );

      blocTest<InvitationsBloc, InvitationsState>(
        'emits [InvitationsLoading, InvitationsLoaded([])] when repo returns empty list',
        build: () {
          when(() => mockRepository.loadInvitations())
              .thenAnswer((_) async => []);
          return bloc;
        },
        act: (bloc) => bloc.add(LoadInvitations()),
        expect: () => [
          isA<InvitationsLoading>(),
          isA<InvitationsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsLoaded;
          expect(state.invitations, isEmpty);
        },
      );

      blocTest<InvitationsBloc, InvitationsState>(
        'emits [InvitationsLoading, InvitationsError] when loadInvitations fails',
        build: () {
          when(() => mockRepository.loadInvitations())
              .thenThrow(Exception('Failed to load'));
          return bloc;
        },
        act: (bloc) => bloc.add(LoadInvitations()),
        expect: () => [
          isA<InvitationsLoading>(),
          isA<InvitationsError>(),
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsError;
          expect(state.message, contains('Failed to load invitations'));
        },
      );
    });

    group('AddInvitation', () {
      final invitation = {'roomId': 'room1', 'inviter': 'user1', 'roomName': 'Test Room'};

      blocTest<InvitationsBloc, InvitationsState>(
        'emits [InvitationsLoaded] with new invitation when invitation does not exist',
        build: () {
          when(() => mockRepository.saveInvitations(any()))
              .thenAnswer((_) async {});
          return bloc;
        },
        act: (bloc) => bloc.add(AddInvitation(invitation)),
        expect: () => [
          isA<InvitationsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsLoaded;
          expect(state.invitations, contains(invitation));
          expect(state.invitations.length, equals(1));
        },
      );

      blocTest<InvitationsBloc, InvitationsState>(
        'does not add duplicate invitation with same roomId',
        build: () {
          when(() => mockRepository.saveInvitations(any()))
              .thenAnswer((_) async {});
          return bloc;
        },
        act: (bloc) {
          bloc.add(AddInvitation(invitation));
          bloc.add(AddInvitation(invitation)); // Try to add same invitation twice
        },
        expect: () => [
          isA<InvitationsLoaded>(), // First addition succeeds
        ],
        verify: (bloc) {
          expect(bloc.totalInvites, equals(1)); // Still only one invitation
        },
      );

      blocTest<InvitationsBloc, InvitationsState>(
        'emits InvitationsError when saveInvitations fails',
        build: () {
          when(() => mockRepository.saveInvitations(any()))
              .thenThrow(Exception('Save failed'));
          return bloc;
        },
        act: (bloc) => bloc.add(AddInvitation(invitation)),
        expect: () => [
          isA<InvitationsError>(),
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsError;
          expect(state.message, contains('Failed to add invitation'));
        },
      );
    });

    group('RemoveInvitation', () {
      final invitation1 = {'roomId': 'room1', 'inviter': 'user1', 'roomName': 'Test Room 1'};
      final invitation2 = {'roomId': 'room2', 'inviter': 'user2', 'roomName': 'Test Room 2'};

      blocTest<InvitationsBloc, InvitationsState>(
        'emits [InvitationsLoaded] without removed invitation',
        build: () {
          when(() => mockRepository.saveInvitations(any())).thenAnswer((_) async {});
          return bloc;
        },
        act: (bloc) {
          // First add the invitations
          bloc.add(AddInvitation(invitation1));
          bloc.add(AddInvitation(invitation2));
          // Then remove one
          bloc.add(const RemoveInvitation('room1'));
        },
        expect: () => [
          isA<InvitationsLoaded>(), // First invitation added
          isA<InvitationsLoaded>(), // Second invitation added  
          isA<InvitationsLoaded>(), // After removal
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsLoaded;
          expect(state.invitations, equals([invitation2]));
          expect(state.invitations.length, equals(1));
        },
      );

      blocTest<InvitationsBloc, InvitationsState>(
        'does not crash when removing nonexistent invitation',
        build: () {
          when(() => mockRepository.saveInvitations(any())).thenAnswer((_) async {});
          return bloc;
        },
        act: (bloc) => bloc.add(const RemoveInvitation('nonexistent')),
        expect: () => [],
      );

      test('emits InvitationsError when saveInvitations fails during removal', () async {
        // Create a new bloc instance for this test
        final testBloc = InvitationsBloc(repository: mockRepository);
        
        // Set up successful save first
        when(() => mockRepository.saveInvitations(any())).thenAnswer((_) async {});
        
        // Add an invitation
        testBloc.add(AddInvitation(invitation1));
        await Future.delayed(const Duration(milliseconds: 50)); // Wait for completion
        
        // Verify it was added
        expect(testBloc.totalInvites, equals(1));
        
        // Now set up the mock to fail on save
        when(() => mockRepository.saveInvitations(any())).thenThrow(Exception('Save failed'));
        
        // Try to remove and expect error
        testBloc.add(const RemoveInvitation('room1'));
        await Future.delayed(const Duration(milliseconds: 50));
        
        final state = testBloc.state;
        expect(state, isA<InvitationsError>());
        final errorState = state as InvitationsError;
        expect(errorState.message, contains('Failed to remove invitation'));
        
        await testBloc.close();
      });
    });

    group('ClearInvitations', () {
      blocTest<InvitationsBloc, InvitationsState>(
        'emits [InvitationsLoaded([])] when clearing invitations succeeds',
        build: () {
          when(() => mockRepository.clearInvitations()).thenAnswer((_) async {});
          return bloc;
        },
        act: (bloc) => bloc.add(ClearInvitations()),
        expect: () => [
          isA<InvitationsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsLoaded;
          expect(state.invitations, isEmpty);
        },
      );

      blocTest<InvitationsBloc, InvitationsState>(
        'emits InvitationsError when clearInvitations fails',
        build: () {
          when(() => mockRepository.clearInvitations())
              .thenThrow(Exception('Clear failed'));
          return bloc;
        },
        act: (bloc) => bloc.add(ClearInvitations()),
        expect: () => [
          isA<InvitationsError>(),
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsError;
          expect(state.message, contains('Failed to clear invitations'));
        },
      );
    });

    group('ProcessSyncInvitation', () {
      blocTest<InvitationsBloc, InvitationsState>(
        'adds new invitation and emits InvitationsLoaded',
        build: () {
          when(() => mockRepository.loadInvitations()).thenAnswer((_) async => []);
          when(() => mockRepository.saveInvitations(any())).thenAnswer((_) async {});
          return bloc;
        },
        act: (bloc) => bloc.add(const ProcessSyncInvitation(
          roomId: 'room1',
          inviter: 'user1',
          roomName: 'Test Room',
        )),
        expect: () => [
          isA<InvitationsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsLoaded;
          expect(state.invitations.length, equals(1));
          expect(state.invitations.first['roomId'], equals('room1'));
          expect(state.invitations.first['inviter'], equals('user1'));
          expect(state.invitations.first['roomName'], equals('Test Room'));
        },
      );

      blocTest<InvitationsBloc, InvitationsState>(
        'does not add duplicate invitation when roomId already exists',
        build: () {
          final existingInvitation = {'roomId': 'room1', 'inviter': 'user1', 'roomName': 'Existing'};
          when(() => mockRepository.loadInvitations()).thenAnswer((_) async => [existingInvitation]);
          when(() => mockRepository.saveInvitations(any())).thenAnswer((_) async {});
          return bloc;
        },
        act: (bloc) => bloc.add(const ProcessSyncInvitation(
          roomId: 'room1',
          inviter: 'user2',
          roomName: 'New Room',
        )),
        expect: () => [
          isA<InvitationsLoaded>(),
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsLoaded;
          expect(state.invitations.length, equals(1));
          expect(state.invitations.first['roomName'], equals('Existing'));
        },
      );

      blocTest<InvitationsBloc, InvitationsState>(
        'emits InvitationsError when processing sync invitation fails',
        build: () {
          when(() => mockRepository.loadInvitations())
              .thenThrow(Exception('Load failed'));
          return bloc;
        },
        act: (bloc) => bloc.add(const ProcessSyncInvitation(
          roomId: 'room1',
          inviter: 'user1',
          roomName: 'Test Room',
        )),
        expect: () => [
          isA<InvitationsError>(),
        ],
        verify: (bloc) {
          final state = bloc.state as InvitationsError;
          expect(state.message, contains('Failed to process sync invitation'));
        },
      );
    });

    group('Getters', () {
      blocTest<InvitationsBloc, InvitationsState>(
        'totalInvites getter returns correct count',
        build: () {
          when(() => mockRepository.saveInvitations(any())).thenAnswer((_) async {});
          return bloc;
        },
        act: (bloc) {
          final invitation1 = {'roomId': 'room1', 'inviter': 'user1', 'roomName': 'Test Room 1'};
          final invitation2 = {'roomId': 'room2', 'inviter': 'user2', 'roomName': 'Test Room 2'};
          bloc.add(AddInvitation(invitation1));
          bloc.add(AddInvitation(invitation2));
        },
        verify: (bloc) {
          expect(bloc.totalInvites, equals(2));
        },
      );

      blocTest<InvitationsBloc, InvitationsState>(
        'invitations getter returns copy of invitations list',
        build: () {
          when(() => mockRepository.saveInvitations(any())).thenAnswer((_) async {});
          return bloc;
        },
        act: (bloc) {
          final invitation = {'roomId': 'room1', 'inviter': 'user1', 'roomName': 'Test Room'};
          bloc.add(AddInvitation(invitation));
        },
        verify: (bloc) {
          final invitationsCopy = bloc.invitations;
          invitationsCopy.clear();
          
          // Original list should still have the invitation
          expect(bloc.invitations.length, equals(1));
          expect(bloc.totalInvites, equals(1));
        },
      );
    });
  });
}