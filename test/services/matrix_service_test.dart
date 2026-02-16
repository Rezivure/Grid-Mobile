import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io' as http;

class MockClient extends Mock implements Client {}
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// Testable version of MatrixService with dependency injection
class TestableMatrixService {
  final Client client;
  final FlutterSecureStorage secureStorage;

  TestableMatrixService({
    required this.client,
    required this.secureStorage,
  });

  Future<void> login(String username, String password) async {
    try {
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
      );
      await secureStorage.write(key: 'access_token', value: client.accessToken);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    await client.logout();
    await secureStorage.delete(key: 'access_token');
  }

  Future<void> restoreSession() async {
    final accessToken = await secureStorage.read(key: 'access_token');
    if (accessToken != null) {
      client.accessToken = accessToken;
      await client.sync();
    }
  }
}

void main() {
  late TestableMatrixService matrixService;
  late MockClient mockClient;
  late MockFlutterSecureStorage mockSecureStorage;

  setUp(() {
    mockClient = MockClient();
    mockSecureStorage = MockFlutterSecureStorage();
    
    matrixService = TestableMatrixService(
      client: mockClient,
      secureStorage: mockSecureStorage,
    );
  });

  group('MatrixService', () {
    group('login', () {
      test('successful login stores access token', () async {
        // Arrange
        const username = 'testuser';
        const password = 'password123';
        const accessToken = 'mock_access_token';
        
        when(() => mockClient.login(
          LoginType.mLoginPassword,
          identifier: any(named: 'identifier'),
          password: password,
        )).thenAnswer((_) async => LoginResponse(
          accessToken: accessToken,
          deviceId: 'device123',
          homeServer: 'https://matrix.example.com',
          userId: '@testuser:example.com',
          wellKnown: null,
        ));
        
        when(() => mockClient.accessToken).thenReturn(accessToken);
        when(() => mockSecureStorage.write(key: 'access_token', value: accessToken))
            .thenAnswer((_) async {});

        // Act
        await matrixService.login(username, password);

        // Assert
        verify(() => mockClient.login(
          LoginType.mLoginPassword,
          identifier: any(named: 'identifier', that: isA<AuthenticationUserIdentifier>()),
          password: password,
        )).called(1);
        
        verify(() => mockSecureStorage.write(key: 'access_token', value: accessToken))
            .called(1);
      });

      test('login failure does not store access token', () async {
        // Arrange
        const username = 'testuser';
        const password = 'wrongpassword';
        
        when(() => mockClient.login(
          LoginType.mLoginPassword,
          identifier: any(named: 'identifier'),
          password: password,
        )).thenThrow(Exception('Login failed'));

        // Act & Assert
        expect(
          () => matrixService.login(username, password),
          throwsA(isA<Exception>()),
        );
        
        verify(() => mockClient.login(
          LoginType.mLoginPassword,
          identifier: any(named: 'identifier'),
          password: password,
        )).called(1);
        
        verifyNever(() => mockSecureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ));
      });

      test('network error during login rethrows exception', () async {
        // Arrange
        const username = 'testuser';
        const password = 'password123';
        
        when(() => mockClient.login(
          LoginType.mLoginPassword,
          identifier: any(named: 'identifier'),
          password: password,
        )).thenThrow(Exception('Network error'));

        // Act & Assert
        expect(
          () => matrixService.login(username, password),
          throwsA(isA<Exception>()),
        );
        
        verifyNever(() => mockSecureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ));
      });

      test('passes correct user identifier to client', () async {
        // Arrange
        const username = 'testuser';
        const password = 'password123';
        
        when(() => mockClient.login(
          LoginType.mLoginPassword,
          identifier: any(named: 'identifier'),
          password: password,
        )).thenAnswer((_) async => LoginResponse(
          accessToken: 'token',
          deviceId: 'device',
          homeServer: 'https://matrix.example.com',
          userId: '@testuser:example.com',
          wellKnown: null,
        ));
        
        when(() => mockClient.accessToken).thenReturn('token');
        when(() => mockSecureStorage.write(key: any(named: 'key'), value: any(named: 'value')))
            .thenAnswer((_) async {});

        // Act
        await matrixService.login(username, password);

        // Assert
        final capturedIdentifier = verify(() => mockClient.login(
          LoginType.mLoginPassword,
          identifier: captureAny(named: 'identifier'),
          password: password,
        )).captured.first as AuthenticationUserIdentifier;
        
        expect(capturedIdentifier.user, equals(username));
      });
    });

    group('logout', () {
      test('successful logout removes stored token', () async {
        // Arrange
        when(() => mockClient.logout()).thenAnswer((_) async {});
        when(() => mockSecureStorage.delete(key: 'access_token'))
            .thenAnswer((_) async {});

        // Act
        await matrixService.logout();

        // Assert
        verify(() => mockClient.logout()).called(1);
        verify(() => mockSecureStorage.delete(key: 'access_token')).called(1);
      });

      test('client logout failure still propagates exception', () async {
        // Arrange
        when(() => mockClient.logout()).thenThrow(Exception('Logout failed'));
        when(() => mockSecureStorage.delete(key: 'access_token'))
            .thenAnswer((_) async {});

        // Act & Assert
        expect(() => matrixService.logout(), throwsA(isA<Exception>()));
        
        verify(() => mockClient.logout()).called(1);
        // The secure storage delete won't be called due to the exception
      });

      test('secure storage deletion failure after successful client logout', () async {
        // Arrange
        when(() => mockClient.logout()).thenAnswer((_) async {});
        when(() => mockSecureStorage.delete(key: 'access_token'))
            .thenThrow(Exception('Storage error'));

        // Act & Assert
        expect(() => matrixService.logout(), throwsA(isA<Exception>()));
        
        // The client logout should complete before storage deletion fails
        await untilCalled(() => mockClient.logout());
        verify(() => mockClient.logout()).called(1);
      });
    });

    group('restoreSession', () {
      test('restores session when access token exists', () async {
        // Arrange
        const accessToken = 'stored_access_token';
        when(() => mockSecureStorage.read(key: 'access_token'))
            .thenAnswer((_) async => accessToken);
        when(() => mockClient.sync()).thenAnswer((_) async => SyncUpdate(
          nextBatch: 'test_batch',
        ));

        // Act
        await matrixService.restoreSession();

        // Assert
        verify(() => mockSecureStorage.read(key: 'access_token')).called(1);
        verify(() => mockClient.accessToken = accessToken).called(1);
        verify(() => mockClient.sync()).called(1);
      });

      test('does nothing when no access token stored', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'access_token'))
            .thenAnswer((_) async => null);

        // Act
        await matrixService.restoreSession();

        // Assert
        verify(() => mockSecureStorage.read(key: 'access_token')).called(1);
        verifyNever(() => mockClient.sync());
        verifyNever(() => mockClient.accessToken = any());
      });

      test('handles sync failure during session restore', () async {
        // Arrange
        const accessToken = 'stored_access_token';
        when(() => mockSecureStorage.read(key: 'access_token'))
            .thenAnswer((_) async => accessToken);
        when(() => mockClient.sync()).thenThrow(Exception('Sync failed'));

        // Act & Assert
        expect(() => matrixService.restoreSession(), throwsA(isA<Exception>()));
        
        // The access token should be set before sync fails
        await untilCalled(() => mockClient.accessToken = accessToken);
        verify(() => mockSecureStorage.read(key: 'access_token')).called(1);
        verify(() => mockClient.accessToken = accessToken).called(1);
      });

      test('handles secure storage read failure', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'access_token'))
            .thenThrow(Exception('Storage read failed'));

        // Act & Assert
        expect(() => matrixService.restoreSession(), throwsA(isA<Exception>()));
        
        verify(() => mockSecureStorage.read(key: 'access_token')).called(1);
        verifyNever(() => mockClient.sync());
        verifyNever(() => mockClient.accessToken = any());
      });

      test('sets access token on client before syncing', () async {
        // Arrange
        const accessToken = 'stored_access_token';
        when(() => mockSecureStorage.read(key: 'access_token'))
            .thenAnswer((_) async => accessToken);
        when(() => mockClient.sync()).thenAnswer((_) async => SyncUpdate(
          nextBatch: 'test_batch',
        ));

        // Act
        await matrixService.restoreSession();

        // Assert - verify order of operations
        verifyInOrder([
          () => mockSecureStorage.read(key: 'access_token'),
          () => mockClient.accessToken = accessToken,
          () => mockClient.sync(),
        ]);
      });
    });

    group('edge cases', () {
      test('handles empty access token from storage', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'access_token'))
            .thenAnswer((_) async => '');
        when(() => mockClient.sync()).thenAnswer((_) async => SyncUpdate(
          nextBatch: 'test_batch',
        ));

        // Act
        await matrixService.restoreSession();

        // Assert - empty string is truthy, so sync should be called
        verify(() => mockSecureStorage.read(key: 'access_token')).called(1);
        verify(() => mockClient.accessToken = '').called(1);
        verify(() => mockClient.sync()).called(1);
      });

      test('preserves login error exceptions', () async {
        // Arrange
        final loginError = Exception('Login failed: invalid credentials');
        
        when(() => mockClient.login(
          any(),
          identifier: any(named: 'identifier'),
          password: any(named: 'password'),
        )).thenThrow(loginError);

        // Act & Assert
        expect(
          () => matrixService.login('user', 'pass'),
          throwsA(loginError),
        );
      });
    });
  });
}