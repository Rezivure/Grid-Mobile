import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;

import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/location_history_repository.dart';
import 'package:grid_frontend/repositories/room_location_history_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';

// Mock classes
class MockClient extends Mock implements Client {}
class MockUserService extends Mock implements UserService {}
class MockLocationManager extends Mock implements LocationManager {}
class MockUserRepository extends Mock implements UserRepository {}
class MockUserKeysRepository extends Mock implements UserKeysRepository {}
class MockRoomRepository extends Mock implements RoomRepository {}
class MockLocationRepository extends Mock implements LocationRepository {}
class MockLocationHistoryRepository extends Mock implements LocationHistoryRepository {}
class MockRoomLocationHistoryRepository extends Mock implements RoomLocationHistoryRepository {}
class MockSharingPreferencesRepository extends Mock implements SharingPreferencesRepository {}
class MockRoom extends Mock implements Room {}
class MockUser extends Mock implements User {}
class MockEvent extends Mock implements Event {}

// Fake classes
class FakeStateEvent extends Fake implements StateEvent {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeStateEvent());
  });

  group('RoomService', () {
    late RoomService roomService;
    late MockClient mockClient;
    late MockUserService mockUserService;
    late MockLocationManager mockLocationManager;
    late MockUserRepository mockUserRepository;
    late MockUserKeysRepository mockUserKeysRepository;
    late MockRoomRepository mockRoomRepository;
    late MockLocationRepository mockLocationRepository;
    late MockLocationHistoryRepository mockLocationHistoryRepository;
    late MockRoomLocationHistoryRepository mockRoomLocationHistoryRepository;
    late MockSharingPreferencesRepository mockSharingPreferencesRepository;

    const testUserId = '@test_user:matrix.org';
    const testRoomId = '!test_room:matrix.org';
    const currentUserId = '@current_user:matrix.org';

    setUp(() {
      mockClient = MockClient();
      mockUserService = MockUserService();
      mockLocationManager = MockLocationManager();
      mockUserRepository = MockUserRepository();
      mockUserKeysRepository = MockUserKeysRepository();
      mockRoomRepository = MockRoomRepository();
      mockLocationRepository = MockLocationRepository();
      mockLocationHistoryRepository = MockLocationHistoryRepository();
      mockRoomLocationHistoryRepository = MockRoomLocationHistoryRepository();
      mockSharingPreferencesRepository = MockSharingPreferencesRepository();

      // Setup location stream
      when(() => mockLocationManager.locationStream).thenAnswer(
        (_) => Stream<bg.Location>.empty(),
      );

      roomService = RoomService(
        mockClient,
        mockUserService,
        mockUserRepository,
        mockUserKeysRepository,
        mockRoomRepository,
        mockLocationRepository,
        mockLocationHistoryRepository,
        mockSharingPreferencesRepository,
        mockLocationManager,
        roomLocationHistoryRepository: mockRoomLocationHistoryRepository,
      );

      // Common setup
      when(() => mockClient.userID).thenReturn(currentUserId);
      when(() => mockClient.homeserver).thenReturn(Uri.parse('https://matrix.org'));
    });

    group('createRoomAndInviteContact', () {
      test('returns false when user does not exist', () async {
        // Arrange
        when(() => mockUserService.userExists(testUserId))
            .thenAnswer((_) async => false);

        // Act
        final result = await roomService.createRoomAndInviteContact(testUserId);

        // Assert
        expect(result, isFalse);
        verify(() => mockUserService.userExists(testUserId)).called(1);
        verifyNever(() => mockClient.createRoom(
          name: any(named: 'name'),
          isDirect: any(named: 'isDirect'),
          preset: any(named: 'preset'),
          invite: any(named: 'invite'),
          initialState: any(named: 'initialState'),
        ));
      });

      test('returns false when user exists check throws exception', () async {
        // Arrange
        when(() => mockUserService.userExists(testUserId))
            .thenThrow(Exception('Network error'));

        // Act
        final result = await roomService.createRoomAndInviteContact(testUserId);

        // Assert
        expect(result, isFalse);
        verify(() => mockUserService.userExists(testUserId)).called(1);
      });

      test('returns false when relationship status is not canInvite', () async {
        // Arrange
        when(() => mockUserService.userExists(testUserId))
            .thenAnswer((_) async => true);
        when(() => mockUserService.getRelationshipStatus(currentUserId, testUserId))
            .thenAnswer((_) async => RelationshipStatus.alreadyFriends);

        // Act
        final result = await roomService.createRoomAndInviteContact(testUserId);

        // Assert
        expect(result, isFalse);
        verify(() => mockUserService.getRelationshipStatus(currentUserId, testUserId)).called(1);
      });

      test('creates room successfully when user exists and can be invited', () async {
        // Arrange
        const expectedRoomName = "Grid:Direct:$currentUserId:$testUserId";
        
        when(() => mockUserService.userExists(testUserId))
            .thenAnswer((_) async => true);
        when(() => mockUserService.getRelationshipStatus(currentUserId, testUserId))
            .thenAnswer((_) async => RelationshipStatus.canInvite);
        when(() => mockClient.createRoom(
          name: any(named: 'name'),
          isDirect: any(named: 'isDirect'),
          preset: any(named: 'preset'),
          invite: any(named: 'invite'),
          initialState: any(named: 'initialState'),
        )).thenAnswer((_) async => testRoomId);

        // Act
        final result = await roomService.createRoomAndInviteContact(testUserId);

        // Assert
        expect(result, isTrue);
        verify(() => mockClient.createRoom(
          name: expectedRoomName,
          isDirect: true,
          preset: CreateRoomPreset.privateChat,
          invite: [testUserId],
          initialState: any(named: 'initialState'),
        )).called(1);
      });

      test('handles room creation failure gracefully', () async {
        // Arrange
        when(() => mockUserService.userExists(testUserId))
            .thenAnswer((_) async => true);
        when(() => mockUserService.getRelationshipStatus(currentUserId, testUserId))
            .thenAnswer((_) async => RelationshipStatus.canInvite);
        when(() => mockClient.createRoom(
          name: any(named: 'name'),
          isDirect: any(named: 'isDirect'),
          preset: any(named: 'preset'),
          invite: any(named: 'invite'),
          initialState: any(named: 'initialState'),
        )).thenThrow(MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Cannot create room'
        }));

        // Act & Assert
        expect(
          () => roomService.createRoomAndInviteContact(testUserId),
          throwsA(isA<MatrixException>()),
        );
      });

      test('handles invalid user ID format', () async {
        // Arrange
        const invalidUserId = 'invalid_user_id';
        
        when(() => mockUserService.userExists(invalidUserId))
            .thenThrow(Exception('Invalid user ID format'));

        // Act
        final result = await roomService.createRoomAndInviteContact(invalidUserId);

        // Assert
        expect(result, isFalse);
      });
    });

    group('getUserRoomMembership', () {
      test('returns membership from room state when available', () async {
        // Arrange
        final mockRoom = MockRoom();
        final mockEvent = MockEvent();
        
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(mockRoom);
        when(() => mockRoom.getState('m.room.member', testUserId)).thenReturn(mockEvent);
        when(() => mockEvent.content).thenReturn({'membership': 'join'});

        // Act
        final result = await roomService.getUserRoomMembership(testRoomId, testUserId);

        // Assert
        expect(result, equals('join'));
        verify(() => mockRoom.getState('m.room.member', testUserId)).called(1);
      });

      test('falls back to participants list when state unavailable', () async {
        // Arrange
        final mockRoom = MockRoom();
        final mockUser = MockUser();
        
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(mockRoom);
        when(() => mockRoom.getState('m.room.member', testUserId)).thenReturn(null);
        when(() => mockRoom.getParticipants()).thenReturn([mockUser]);
        when(() => mockUser.id).thenReturn(testUserId);
        when(() => mockUser.membership).thenReturn(Membership.join);

        // Act
        final result = await roomService.getUserRoomMembership(testRoomId, testUserId);

        // Assert
        expect(result, equals('join'));
        verify(() => mockRoom.getParticipants()).called(1);
      });

      test('assumes invite for direct rooms when user not found in participants', () async {
        // Arrange
        final mockRoom = MockRoom();
        
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(mockRoom);
        when(() => mockRoom.getState('m.room.member', testUserId)).thenReturn(null);
        when(() => mockRoom.getParticipants()).thenReturn([]);
        when(() => mockRoom.name).thenReturn('Grid:Direct:user1:user2');

        // Act
        final result = await roomService.getUserRoomMembership(testRoomId, testUserId);

        // Assert
        expect(result, equals('invite'));
      });

      test('returns null when room not found', () async {
        // Arrange
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(null);

        // Act
        final result = await roomService.getUserRoomMembership(testRoomId, testUserId);

        // Assert
        expect(result, isNull);
      });

      test('handles membership state retrieval exception', () async {
        // Arrange
        final mockRoom = MockRoom();
        
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(mockRoom);
        when(() => mockRoom.getState('m.room.member', testUserId))
            .thenThrow(Exception('State access failed'));
        when(() => mockRoom.getParticipants()).thenReturn([]);
        when(() => mockRoom.name).thenReturn('Regular Room');

        // Act
        final result = await roomService.getUserRoomMembership(testRoomId, testUserId);

        // Assert
        expect(result, isNull);
      });
    });

    group('leaveRoom', () {
      test('successfully leaves room and cleans up data', () async {
        // Arrange
        final mockRoom = MockRoom();
        
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(mockRoom);
        when(() => mockRoom.leave()).thenAnswer((_) async {});
        when(() => mockClient.forgetRoom(testRoomId)).thenAnswer((_) async {});
        when(() => mockRoomRepository.leaveRoom(testRoomId, currentUserId))
            .thenAnswer((_) async {});

        // Act
        final result = await roomService.leaveRoom(testRoomId);

        // Assert
        expect(result, isTrue);
        verify(() => mockRoom.leave()).called(1);
        verify(() => mockClient.forgetRoom(testRoomId)).called(1);
        verify(() => mockRoomRepository.leaveRoom(testRoomId, currentUserId)).called(1);
      });

      test('continues with local cleanup when Matrix leave fails', () async {
        // Arrange
        final mockRoom = MockRoom();
        
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(mockRoom);
        when(() => mockRoom.leave()).thenThrow(Exception('Network error'));
        when(() => mockRoomRepository.leaveRoom(testRoomId, currentUserId))
            .thenAnswer((_) async {});

        // Act
        final result = await roomService.leaveRoom(testRoomId);

        // Assert
        expect(result, isTrue);
        verify(() => mockRoomRepository.leaveRoom(testRoomId, currentUserId)).called(1);
      });

      test('handles case when room not found in client', () async {
        // Arrange
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(null);
        when(() => mockRoomRepository.leaveRoom(testRoomId, currentUserId))
            .thenAnswer((_) async {});

        // Act
        final result = await roomService.leaveRoom(testRoomId);

        // Assert
        expect(result, isTrue);
        verify(() => mockRoomRepository.leaveRoom(testRoomId, currentUserId)).called(1);
      });

      test('returns false when local cleanup fails', () async {
        // Arrange
        final mockRoom = MockRoom();
        
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(mockRoom);
        when(() => mockRoom.leave()).thenAnswer((_) async {});
        when(() => mockClient.forgetRoom(testRoomId)).thenAnswer((_) async {});
        when(() => mockRoomRepository.leaveRoom(testRoomId, currentUserId))
            .thenThrow(Exception('Database error'));

        // Act
        final result = await roomService.leaveRoom(testRoomId);

        // Assert
        expect(result, isFalse);
      });

      test('handles user ID not found scenario', () async {
        // Arrange
        when(() => mockClient.userID).thenReturn(null);

        // Act
        final result = await roomService.leaveRoom(testRoomId);

        // Assert
        expect(result, isFalse);
      });
    });

    group('isUserInRoom', () {
      test('returns true when user is in room participants', () async {
        // Arrange
        final mockRoom = MockRoom();
        final mockUser = MockUser();
        
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(mockRoom);
        when(() => mockRoom.getParticipants()).thenReturn([mockUser]);
        when(() => mockUser.id).thenReturn(testUserId);

        // Act
        final result = await roomService.isUserInRoom(testRoomId, testUserId);

        // Assert
        expect(result, isTrue);
      });

      test('returns false when user is not in room participants', () async {
        // Arrange
        final mockRoom = MockRoom();
        final mockUser = MockUser();
        
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(mockRoom);
        when(() => mockRoom.getParticipants()).thenReturn([mockUser]);
        when(() => mockUser.id).thenReturn('@other_user:matrix.org');

        // Act
        final result = await roomService.isUserInRoom(testRoomId, testUserId);

        // Assert
        expect(result, isFalse);
      });

      test('returns false when room not found', () async {
        // Arrange
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(null);

        // Act
        final result = await roomService.isUserInRoom(testRoomId, testUserId);

        // Assert
        expect(result, isFalse);
      });
    });

    group('getUserPowerLevel', () {
      test('returns power level when room exists', () {
        // Arrange
        final mockRoom = MockRoom();
        const expectedPowerLevel = 50;
        
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(mockRoom);
        when(() => mockRoom.getPowerLevelByUserId(testUserId)).thenReturn(expectedPowerLevel);

        // Act
        final result = roomService.getUserPowerLevel(testRoomId, testUserId);

        // Assert
        expect(result, equals(expectedPowerLevel));
      });

      test('returns 0 when room not found', () {
        // Arrange
        when(() => mockClient.getRoomById(testRoomId)).thenReturn(null);

        // Act
        final result = roomService.getUserPowerLevel(testRoomId, testUserId);

        // Assert
        expect(result, equals(0));
      });
    });

    group('homeserver information', () {
      test('getMyHomeserver returns correct homeserver', () {
        // Arrange
        when(() => mockClient.homeserver).thenReturn(Uri.parse('https://example.com'));

        // Act
        final result = roomService.getMyHomeserver();

        // Assert
        expect(result, equals('https://example.com'));
      });
    });

    group('room name validation', () {
      test('direct room names follow correct format', () async {
        // Test the room naming convention for direct rooms
        const user1 = '@alice:matrix.org';
        const user2 = '@bob:matrix.org';
        const expectedFormat = 'Grid:Direct:$user1:$user2';
        
        // The format should be predictable and include both user IDs
        expect(expectedFormat.startsWith('Grid:Direct:'), isTrue);
        expect(expectedFormat.contains(user1), isTrue);
        expect(expectedFormat.contains(user2), isTrue);
      });
    });

    group('invite edge cases', () {
      test('handles already invited user gracefully', () async {
        // Arrange
        when(() => mockUserService.userExists(testUserId))
            .thenAnswer((_) async => true);
        when(() => mockUserService.getRelationshipStatus(currentUserId, testUserId))
            .thenAnswer((_) async => RelationshipStatus.invitationSent);

        // Act
        final result = await roomService.createRoomAndInviteContact(testUserId);

        // Assert
        expect(result, isFalse);
      });

      test('handles self-invitation attempt', () async {
        // Arrange - trying to invite self
        when(() => mockUserService.userExists(currentUserId))
            .thenAnswer((_) async => true);
        when(() => mockUserService.getRelationshipStatus(currentUserId, currentUserId))
            .thenAnswer((_) async => RelationshipStatus.alreadyFriends);

        // Act
        final result = await roomService.createRoomAndInviteContact(currentUserId);

        // Assert
        expect(result, isFalse);
      });
    });

    group('room encryption', () {
      test('created rooms have encryption enabled', () async {
        // Arrange
        when(() => mockUserService.userExists(testUserId))
            .thenAnswer((_) async => true);
        when(() => mockUserService.getRelationshipStatus(currentUserId, testUserId))
            .thenAnswer((_) async => RelationshipStatus.canInvite);
        when(() => mockClient.createRoom(
          name: any(named: 'name'),
          isDirect: any(named: 'isDirect'),
          preset: any(named: 'preset'),
          invite: any(named: 'invite'),
          initialState: any(named: 'initialState'),
        )).thenAnswer((_) async => testRoomId);

        // Act
        await roomService.createRoomAndInviteContact(testUserId);

        // Assert - verify encryption state is set
        final captured = verify(() => mockClient.createRoom(
          name: any(named: 'name'),
          isDirect: any(named: 'isDirect'),
          preset: any(named: 'preset'),
          invite: any(named: 'invite'),
          initialState: captureAny(named: 'initialState'),
        )).captured.first as List<StateEvent>;
        
        expect(captured, isNotEmpty);
        expect(captured.any((event) => event.type == 'm.room.encryption'), isTrue);
      });
    });

    group('error scenarios', () {
      test('handles Matrix server errors gracefully', () async {
        // Arrange
        when(() => mockUserService.userExists(testUserId))
            .thenThrow(MatrixException.fromJson({
              'errcode': 'M_UNKNOWN',
              'error': 'Server error'
            }));

        // Act
        final result = await roomService.createRoomAndInviteContact(testUserId);

        // Assert
        expect(result, isFalse);
      });

      test('handles network timeout during user existence check', () async {
        // Arrange
        when(() => mockUserService.userExists(testUserId))
            .thenThrow(Exception('Connection timeout'));

        // Act
        final result = await roomService.createRoomAndInviteContact(testUserId);

        // Assert
        expect(result, isFalse);
      });

      test('handles invalid room ID during operations', () async {
        // Arrange
        const invalidRoomId = 'invalid_room_id';
        
        when(() => mockClient.getRoomById(invalidRoomId)).thenReturn(null);

        // Act
        final result = await roomService.getUserRoomMembership(invalidRoomId, testUserId);

        // Assert
        expect(result, isNull);
      });
    });
  });
}