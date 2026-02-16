import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/services/database_service.dart';

// Mock classes
class MockDatabaseService extends Mock implements DatabaseService {}
class MockDatabase extends Mock implements Database {}

void main() {
  group('UserKeysRepository', () {
    late UserKeysRepository repository;
    late MockDatabaseService mockDatabaseService;
    late MockDatabase mockDatabase;

    const testUserId = 'test_user_123';
    const testPublicKey = 'test_public_key_abcdef';
    const testPrivateKey = 'test_private_key_123456';

    setUp(() {
      mockDatabase = MockDatabase();
      mockDatabaseService = MockDatabaseService();
      repository = UserKeysRepository(mockDatabaseService);

      // Setup common mocks
      when(() => mockDatabaseService.database).thenAnswer((_) async => mockDatabase);
      
      // Register fallback values
      registerFallbackValue(<String, dynamic>{});
    });

    group('key storage and retrieval', () {
      test('stores user keys successfully', () async {
        // Arrange
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((_) async => 1);

        // Act
        await repository.storeKeys(testUserId, testPublicKey, testPrivateKey);

        // Assert
        verify(() => mockDatabase.insert(
          'UserKeys',
          any(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        )).called(1);
      });

      test('retrieves user keys successfully', () async {
        // Arrange
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => [{
          'userId': testUserId,
          'publicKey': testPublicKey,
          'privateKey': testPrivateKey,
        }]);

        // Act
        final result = await repository.getKeys(testUserId);

        // Assert
        expect(result, isNotNull);
        expect(result!['publicKey'], equals(testPublicKey));
        expect(result!['privateKey'], equals(testPrivateKey));
        
        verify(() => mockDatabase.query(
          'UserKeys',
          where: 'userId = ?',
          whereArgs: [testUserId],
        )).called(1);
      });

      test('returns null when no keys exist for user', () async {
        // Arrange
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => []);

        // Act
        final result = await repository.getKeys(testUserId);

        // Assert
        expect(result, isNull);
      });

      test('deletes user keys successfully', () async {
        // Arrange
        when(() => mockDatabase.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => 1);

        // Act
        await repository.deleteKeys(testUserId);

        // Assert
        verify(() => mockDatabase.delete(
          'UserKeys',
          where: 'userId = ?',
          whereArgs: [testUserId],
        )).called(1);
      });
    });

    group('error handling', () {
      test('handles database connection errors during storage', () async {
        // Arrange
        when(() => mockDatabaseService.database)
            .thenThrow(Exception('Database connection failed'));

        // Act & Assert
        expect(
          () => repository.storeKeys(testUserId, testPublicKey, testPrivateKey),
          throwsA(isA<Exception>()),
        );
      });

      test('handles database query errors during retrieval', () async {
        // Arrange
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenThrow(Exception('Database query failed'));

        // Act & Assert
        expect(
          () => repository.getKeys(testUserId),
          throwsA(isA<Exception>()),
        );
      });

      test('handles database deletion errors', () async {
        // Arrange
        when(() => mockDatabase.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenThrow(Exception('Database delete failed'));

        // Act & Assert
        expect(
          () => repository.deleteKeys(testUserId),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('key validation', () {
      test('handles empty keys gracefully', () async {
        // Arrange
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((_) async => 1);

        // Act - should not throw with empty keys
        await repository.storeKeys(testUserId, '', '');

        // Assert
        verify(() => mockDatabase.insert(
          'UserKeys',
          any(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        )).called(1);
      });

      test('handles null values in database gracefully', () async {
        // Arrange
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => [{
          'userId': testUserId,
          'publicKey': null,
          'privateKey': null,
        }]);

        // Act
        final result = await repository.getKeys(testUserId);

        // Assert
        expect(result, isNotNull);
        expect(result!['publicKey'], isNull);
        expect(result!['privateKey'], isNull);
      });

      test('validates user ID format', () async {
        // Test with various user ID formats
        const validUserId = '@user:matrix.org';
        const invalidUserId = 'invalid_user_id';
        
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((_) async => 1);

        // Should handle both valid and invalid formats
        await repository.storeKeys(validUserId, testPublicKey, testPrivateKey);
        await repository.storeKeys(invalidUserId, testPublicKey, testPrivateKey);

        verify(() => mockDatabase.insert(
          'UserKeys',
          any(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        )).called(2);
      });
    });

    group('concurrent operations', () {
      test('handles concurrent storage operations', () async {
        // Arrange
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((_) async => 1);

        // Act - simulate concurrent storage
        final futures = List.generate(3, (i) => 
          repository.storeKeys('user$i', 'pubkey$i', 'privkey$i')
        );
        
        await Future.wait(futures);

        // Assert - all operations should complete
        verify(() => mockDatabase.insert(
          'UserKeys',
          any(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        )).called(3);
      });

      test('handles concurrent read operations', () async {
        // Arrange
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => [{
          'userId': testUserId,
          'publicKey': testPublicKey,
          'privateKey': testPrivateKey,
        }]);

        // Act - simulate concurrent reads
        final futures = List.generate(3, (_) => repository.getKeys(testUserId));
        final results = await Future.wait(futures);

        // Assert - all should return the same data
        expect(results.length, equals(3));
        expect(results.every((r) => r != null && r['publicKey'] == testPublicKey), isTrue);
      });
    });

    group('data integrity', () {
      test('keys are stored exactly as provided', () async {
        // Arrange
        const specialCharsKey = 'key_with_special_chars_!@#$%^&*()_+{}[]|\\:";\'<>?,./';
        const unicodeKey = 'key_with_unicode_🔑🗝️🔐';
        
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((_) async => 1);

        // Act
        await repository.storeKeys(testUserId, specialCharsKey, unicodeKey);

        // Assert - verify the exact data is stored
        final capturedCall = verify(() => mockDatabase.insert(
          'UserKeys',
          captureAny(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        ));
        
        final capturedData = capturedCall.captured.first as Map<String, dynamic>;
        expect(capturedData['publicKey'], equals(specialCharsKey));
        expect(capturedData['privateKey'], equals(unicodeKey));
      });

      test('overwrites existing keys for same user', () async {
        // Arrange
        const oldPublicKey = 'old_public_key';
        const newPublicKey = 'new_public_key';
        
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((_) async => 1);

        // Act - store twice for same user
        await repository.storeKeys(testUserId, oldPublicKey, testPrivateKey);
        await repository.storeKeys(testUserId, newPublicKey, testPrivateKey);

        // Assert - both calls use REPLACE conflict algorithm
        verify(() => mockDatabase.insert(
          'UserKeys',
          any(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        )).called(2);
      });
    });

    group('table operations', () {
      test('handles empty table gracefully', () async {
        // Arrange
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => []);

        // Act
        final result = await repository.getKeys('nonexistent_user');

        // Assert
        expect(result, isNull);
      });

      test('cleanup operations work correctly', () async {
        // Test that repository can handle cleanup operations
        when(() => mockDatabase.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => 5); // 5 keys deleted

        await repository.deleteKeys(testUserId);

        verify(() => mockDatabase.delete(
          'UserKeys',
          where: 'userId = ?',
          whereArgs: [testUserId],
        )).called(1);
      });
    });
  });
}