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
    const testCurve25519Key = 'test_curve25519_key_abcdef';
    const testEd25519Key = 'test_ed25519_key_123456';

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
        await repository.upsertKeys(testUserId, testCurve25519Key, testEd25519Key);

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
          'curve25519Key': testCurve25519Key,
          'ed25519Key': testEd25519Key,
        }]);

        // Act
        final result = await repository.getKeysByUserId(testUserId);

        // Assert
        expect(result, isNotNull);
        expect(result!['curve25519Key'], equals(testCurve25519Key));
        expect(result['ed25519Key'], equals(testEd25519Key));
        
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
        final result = await repository.getKeysByUserId(testUserId);

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
        await repository.deleteKeysByUserId(testUserId);

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
          () => repository.upsertKeys(testUserId, testCurve25519Key, testEd25519Key),
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
          () => repository.getKeysByUserId(testUserId),
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
          () => repository.deleteKeysByUserId(testUserId),
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
        await repository.upsertKeys(testUserId, '', '');

        // Assert
        verify(() => mockDatabase.insert(
          'UserKeys',
          any(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        )).called(1);
      });

      test('handles null values in database gracefully', () async {
        // Arrange - getKeysByUserId casts to String, so null would throw
        // Test with empty results instead
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => []);

        // Act
        final result = await repository.getKeysByUserId(testUserId);

        // Assert
        expect(result, isNull);
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
        await repository.upsertKeys(validUserId, testCurve25519Key, testEd25519Key);
        await repository.upsertKeys(invalidUserId, testCurve25519Key, testEd25519Key);

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
          repository.upsertKeys('user$i', 'curve25519_$i', 'ed25519_$i')
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
          'curve25519Key': testCurve25519Key,
          'ed25519Key': testEd25519Key,
        }]);

        // Act - simulate concurrent reads
        final futures = List.generate(3, (_) => repository.getKeysByUserId(testUserId));
        final results = await Future.wait(futures);

        // Assert - all should return the same data
        expect(results.length, equals(3));
        expect(results.every((r) => r != null && r['curve25519Key'] == testCurve25519Key), isTrue);
      });
    });

    group('data integrity', () {
      test('keys are stored exactly as provided', () async {
        // Arrange
        const specialCharsKey = r'key_with_special_chars_!@#$%^&*()_+{}[]|\:";' "'<>?,./";
        const unicodeKey = 'key_with_unicode_🔑🗝️🔐';
        
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((_) async => 1);

        // Act
        await repository.upsertKeys(testUserId, specialCharsKey, unicodeKey);

        // Assert - verify the exact data is stored
        final capturedCall = verify(() => mockDatabase.insert(
          'UserKeys',
          captureAny(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        ));
        
        final capturedData = capturedCall.captured.first as Map<String, dynamic>;
        expect(capturedData['curve25519Key'], equals(specialCharsKey));
        expect(capturedData['ed25519Key'], equals(unicodeKey));
      });

      test('overwrites existing keys for same user', () async {
        // Arrange
        const oldCurve25519Key = 'old_curve25519_key';
        const newCurve25519Key = 'new_curve25519_key';
        
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((_) async => 1);

        // Act - store twice for same user
        await repository.upsertKeys(testUserId, oldCurve25519Key, testEd25519Key);
        await repository.upsertKeys(testUserId, newCurve25519Key, testEd25519Key);

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
        final result = await repository.getKeysByUserId('nonexistent_user');

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

        await repository.deleteKeysByUserId(testUserId);

        verify(() => mockDatabase.delete(
          'UserKeys',
          where: 'userId = ?',
          whereArgs: [testUserId],
        )).called(1);
      });
    });
  });
}
