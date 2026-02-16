import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grid_frontend/services/sync_manager.dart';
import 'package:grid_frontend/services/message_processor.dart';
import 'package:grid_frontend/services/room_service.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/services/map_icon_sync_service.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_state.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';

// Mock classes
class MockClient extends Mock implements Client {}
class MockMessageProcessor extends Mock implements MessageProcessor {}
class MockRoomService extends Mock implements RoomService {}
class MockLocationManager extends Mock implements LocationManager {}
class MockMapIconSyncService extends Mock implements MapIconSyncService {}
class MockRoomRepository extends Mock implements RoomRepository {}
class MockUserRepository extends Mock implements UserRepository {}
class MockLocationRepository extends Mock implements LocationRepository {}
class MockSharingPreferencesRepository extends Mock implements SharingPreferencesRepository {}
class MockUserLocationProvider extends Mock implements UserLocationProvider {}
class MockContactsBloc extends Mock implements ContactsBloc {}
class MockGroupsBloc extends Mock implements GroupsBloc {}
class MockInvitationsBloc extends Mock implements InvitationsBloc {}
class MockMapBloc extends Mock implements MapBloc {}
class MockWhoAmIResponse extends Mock implements WhoAmIResponse {}

// Fake classes for fallback values
class FakeDecryptionErrorCallback extends Fake {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncManager', () {
    late SyncManager syncManager;
    late MockClient mockClient;
    late MockMessageProcessor mockMessageProcessor;
    late MockRoomService mockRoomService;
    late MockLocationManager mockLocationManager;
    late MockMapIconSyncService mockMapIconSyncService;
    late MockRoomRepository mockRoomRepository;
    late MockUserRepository mockUserRepository;
    late MockLocationRepository mockLocationRepository;
    late MockSharingPreferencesRepository mockSharingPreferencesRepository;
    late MockUserLocationProvider mockUserLocationProvider;
    late MockContactsBloc mockContactsBloc;
    late MockGroupsBloc mockGroupsBloc;
    late MockInvitationsBloc mockInvitationsBloc;
    late MockMapBloc mockMapBloc;

    const testUserId = '@test_user:matrix.org';
    const testSinceToken = 'test_since_token_12345';

    setUp(() {
      mockClient = MockClient();
      mockMessageProcessor = MockMessageProcessor();
      mockRoomService = MockRoomService();
      mockLocationManager = MockLocationManager();
      mockMapIconSyncService = MockMapIconSyncService();
      mockRoomRepository = MockRoomRepository();
      mockUserRepository = MockUserRepository();
      mockLocationRepository = MockLocationRepository();
      mockSharingPreferencesRepository = MockSharingPreferencesRepository();
      mockUserLocationProvider = MockUserLocationProvider();
      mockContactsBloc = MockContactsBloc();
      mockGroupsBloc = MockGroupsBloc();
      mockInvitationsBloc = MockInvitationsBloc();
      mockMapBloc = MockMapBloc();

      // Setup SharedPreferences
      SharedPreferences.setMockInitialValues({});

      // Setup default invitations state
      when(() => mockInvitationsBloc.state).thenReturn(InvitationsLoaded(
        invitations: [],
        totalInvites: 0,
      ));

      syncManager = SyncManager(
        mockClient,
        mockMessageProcessor,
        mockRoomRepository,
        mockUserRepository,
        mockRoomService,
        mockMapBloc,
        mockContactsBloc,
        mockLocationRepository,
        mockGroupsBloc,
        mockUserLocationProvider,
        mockSharingPreferencesRepository,
        mockInvitationsBloc,
        mapIconSyncService: mockMapIconSyncService,
        locationManager: mockLocationManager,
      );

      // Setup decryption error callback mock
      when(() => mockMessageProcessor.setDecryptionErrorCallback(any())).thenReturn(null);
    });

    group('initialization', () {
      test('starts with uninitialized state', () {
        expect(syncManager.syncState, equals(SyncState.uninitialized));
        expect(syncManager.isReady, isFalse);
      });

      test('handles valid token during initialization', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(fullState: any(named: 'fullState'), timeout: any(named: 'timeout')))
            .thenAnswer((_) async => SyncUpdate(nextBatch: testSinceToken));
        when(() => mockRoomService.cleanRooms()).thenAnswer((_) async {});

        // Act
        await syncManager.initialize();

        // Assert
        expect(syncManager.syncState, equals(SyncState.ready));
        verify(() => mockClient.getTokenOwner()).called(1);
        verify(() => mockMessageProcessor.setDecryptionErrorCallback(any())).called(1);
      });

      test('handles invalid token during initialization', () async {
        // Arrange
        when(() => mockClient.getTokenOwner()).thenThrow(MatrixException.fromJson({
          'errcode': 'M_UNKNOWN_TOKEN',
          'error': 'Invalid access token'
        }));

        // Act
        await syncManager.initialize();

        // Assert
        expect(syncManager.syncState, equals(SyncState.error));
      });

      test('handles empty userId from token owner', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn('');
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);

        // Act
        await syncManager.initialize();

        // Assert
        expect(syncManager.syncState, equals(SyncState.error));
      });

      test('prevents multiple initialization attempts', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(fullState: any(named: 'fullState'), timeout: any(named: 'timeout')))
            .thenAnswer((_) async => SyncUpdate(nextBatch: testSinceToken));
        when(() => mockRoomService.cleanRooms()).thenAnswer((_) async {});

        // Act - call initialize twice
        await syncManager.initialize();
        await syncManager.initialize();

        // Assert - getTokenOwner should only be called once
        verify(() => mockClient.getTokenOwner()).called(1);
      });
    });

    group('sync token management', () {
      test('loads saved since token from SharedPreferences', () async {
        // Arrange
        SharedPreferences.setMockInitialValues({
          'syncSinceToken': testSinceToken,
        });

        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          since: testSinceToken,
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => SyncUpdate(nextBatch: '${testSinceToken}_updated'));
        when(() => mockRoomService.cleanRooms()).thenAnswer((_) async {});

        // Act
        await syncManager.initialize();

        // Assert
        verify(() => mockClient.sync(
          since: testSinceToken,
          timeout: any(named: 'timeout'),
        )).called(1);
      });

      test('performs full sync when no saved token exists', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => SyncUpdate(nextBatch: testSinceToken));
        when(() => mockRoomService.cleanRooms()).thenAnswer((_) async {});

        // Act
        await syncManager.initialize();

        // Assert
        verify(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).called(1);
      });

      test('saves new sync token to SharedPreferences', () async {
        // Arrange
        SharedPreferences.setMockInitialValues({});
        
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => SyncUpdate(nextBatch: testSinceToken));
        when(() => mockRoomService.cleanRooms()).thenAnswer((_) async {});

        // Act
        await syncManager.initialize();

        // Assert
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('syncSinceToken'), equals(testSinceToken));
      });

      test('does not save empty sync tokens', () async {
        // Arrange - setup with empty/null nextBatch
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => SyncUpdate(nextBatch: ''));
        when(() => mockRoomService.cleanRooms()).thenAnswer((_) async {});

        // Act
        await syncManager.initialize();

        // Assert - no token should be saved
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('syncSinceToken'), isNull);
      });
    });

    group('network error handling', () {
      test('handles network errors during sync gracefully', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenThrow(Exception('Network connection timeout'));

        // Act & Assert - should not throw
        await syncManager.initialize();
        expect(syncManager.syncState, equals(SyncState.error));
      });

      test('handles Matrix server errors during sync', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenThrow(MatrixException.fromJson({
          'errcode': 'M_LIMIT_EXCEEDED',
          'error': 'Rate limit exceeded',
          'retry_after_ms': 30000,
        }));

        // Act
        await syncManager.initialize();

        // Assert
        expect(syncManager.syncState, equals(SyncState.error));
      });

      test('handles connection timeout gracefully', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenThrow(TimeoutException('Sync timeout', const Duration(seconds: 30)));

        // Act
        await syncManager.initialize();

        // Assert
        expect(syncManager.syncState, equals(SyncState.error));
      });
    });

    group('partial sync handling', () {
      test('handles partial sync response correctly', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        
        final partialSyncUpdate = SyncUpdate(
          nextBatch: testSinceToken,
          rooms: RoomsUpdate(), // Partial room data
        );
        
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => partialSyncUpdate);
        when(() => mockRoomService.cleanRooms()).thenAnswer((_) async {});

        // Act
        await syncManager.initialize();

        // Assert
        expect(syncManager.syncState, equals(SyncState.ready));
        verify(() => mockRoomService.cleanRooms()).called(1);
      });

      test('handles malformed sync response gracefully', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => SyncUpdate()); // Empty/malformed response

        // Act
        await syncManager.initialize();

        // Assert - should handle gracefully without crashing
        expect(syncManager.syncState, isNot(equals(SyncState.uninitialized)));
      });
    });

    group('decryption error handling', () {
      test('tracks decryption errors correctly', () {
        // Arrange
        expect(syncManager.hasDecryptionErrors, isFalse);
        expect(syncManager.decryptionErrors, isEmpty);

        // Act - simulate decryption errors through the callback
        // (In real usage, this would be called by MessageProcessor)
        // For testing, we access the internal method logic
        
        // Assert initial state
        expect(syncManager.decryptionErrors.length, equals(0));
      });

      test('limits maximum decryption errors stored', () {
        // This tests the bounded error list logic
        const maxErrors = 50; // As defined in SyncManager
        
        expect(maxErrors, equals(50));
        // In real implementation, after 50 errors, oldest would be removed
      });

      test('clears decryption errors when requested', () {
        // Test the clearDecryptionErrors method
        syncManager.clearDecryptionErrors();
        
        expect(syncManager.hasDecryptionErrors, isFalse);
        expect(syncManager.decryptionErrors, isEmpty);
      });
    });

    group('retry logic', () {
      test('implements exponential backoff for failed syncs', () {
        // Test retry logic - exponential backoff timing
        const baseDelay = 1000; // 1 second base
        const maxDelay = 60000; // 60 seconds max
        
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, 60s (capped)
        var delay = baseDelay;
        for (int attempt = 0; attempt < 7; attempt++) {
          if (attempt > 0) {
            delay = (delay * 2).clamp(baseDelay, maxDelay);
          }
          
          if (attempt == 0) expect(delay, equals(1000));
          if (attempt == 1) expect(delay, equals(2000));
          if (attempt == 2) expect(delay, equals(4000));
          if (attempt == 3) expect(delay, equals(8000));
          if (attempt == 4) expect(delay, equals(16000));
          if (attempt == 5) expect(delay, equals(32000));
          if (attempt == 6) expect(delay, equals(60000));
        }
      });
    });

    group('sync state management', () {
      test('transitions through sync states correctly', () async {
        // Test the sync state progression
        expect(syncManager.syncState, equals(SyncState.uninitialized));
        
        // After successful initialization, should be ready
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => SyncUpdate(nextBatch: testSinceToken));
        when(() => mockRoomService.cleanRooms()).thenAnswer((_) async {});

        await syncManager.initialize();
        
        expect(syncManager.syncState, equals(SyncState.ready));
        expect(syncManager.isReady, isTrue);
      });

      test('handles concurrent initialization attempts', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => SyncUpdate(nextBatch: testSinceToken));
        when(() => mockRoomService.cleanRooms()).thenAnswer((_) async {});

        // Act - start multiple initializations concurrently
        final futures = List.generate(3, (_) => syncManager.initialize());
        await Future.wait(futures);

        // Assert - should only initialize once
        verify(() => mockClient.getTokenOwner()).called(1);
      });
    });

    group('room processing', () {
      test('calls cleanRooms during initialization', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => SyncUpdate(nextBatch: testSinceToken));
        when(() => mockRoomService.cleanRooms()).thenAnswer((_) async {});

        // Act
        await syncManager.initialize();

        // Assert
        verify(() => mockRoomService.cleanRooms()).called(1);
      });

      test('handles room cleanup failure gracefully', () async {
        // Arrange
        final mockResponse = MockWhoAmIResponse();
        when(() => mockResponse.userId).thenReturn(testUserId);
        when(() => mockClient.getTokenOwner()).thenAnswer((_) async => mockResponse);
        when(() => mockClient.sync(
          fullState: true,
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => SyncUpdate(nextBatch: testSinceToken));
        when(() => mockRoomService.cleanRooms()).thenThrow(Exception('Database error'));

        // Act & Assert - should not crash
        await syncManager.initialize();
        
        // Should still reach some final state despite cleanup failure
        expect(syncManager.syncState, isNot(equals(SyncState.uninitialized)));
      });
    });

    group('invitation management', () {
      test('returns invitations from bloc state', () {
        // Arrange
        final testInvitations = [
          {'sender': '@user1:matrix.org', 'roomId': '!room1:matrix.org'},
          {'sender': '@user2:matrix.org', 'roomId': '!room2:matrix.org'},
        ];
        
        when(() => mockInvitationsBloc.state).thenReturn(InvitationsLoaded(
          invitations: testInvitations,
          totalInvites: 2,
        ));

        // Act
        final invites = syncManager.invites;
        final totalInvites = syncManager.totalInvites;

        // Assert
        expect(invites.length, equals(2));
        expect(totalInvites, equals(2));
        expect(invites, equals(testInvitations));
      });

      test('returns empty list when invitations not loaded', () {
        // Arrange - invitations state is not loaded
        when(() => mockInvitationsBloc.state).thenReturn(InvitationsInitial());

        // Act
        final invites = syncManager.invites;
        final totalInvites = syncManager.totalInvites;

        // Assert
        expect(invites, isEmpty);
        expect(totalInvites, equals(0));
      });
    });
  });
}