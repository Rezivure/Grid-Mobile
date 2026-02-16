import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/models/user_location.dart';

class MockDatabaseService extends Mock implements DatabaseService {}
class MockDatabase extends Mock implements Database {}

void main() {
  late LocationRepository repository;
  late MockDatabaseService mockDatabaseService;
  late MockDatabase mockDatabase;

  setUp(() {
    mockDatabase = MockDatabase();
    mockDatabaseService = MockDatabaseService();
    repository = LocationRepository(mockDatabaseService);

    when(() => mockDatabaseService.database).thenAnswer((_) async => mockDatabase);
    when(() => mockDatabaseService.getEncryptionKey()).thenAnswer((_) async => 'test_key_base64==');
    registerFallbackValue(<String, dynamic>{});
  });

  group('LocationRepository', () {
    group('locationUpdates stream', () {
      test('is a broadcast stream', () {
        expect(repository.locationUpdates.isBroadcast, isTrue);
      });
    });

    group('insertLocation', () {
      // Note: insertLocation calls location.toMap(encryptionKey) which encrypts data.
      // This requires a valid 32-byte base64 key and valid base64 IV.
      // We test at the repository layer by verifying db.insert is called.
      
      test('calls db.insert and emits on stream', () async {
        // Use a valid 32-byte AES key (base64 encoded)
        final validKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='; // 32 bytes
        final validIv = 'AAAAAAAAAAAAAAAAAAAAAA=='; // 16 bytes
        
        when(() => mockDatabaseService.getEncryptionKey())
            .thenAnswer((_) async => validKey);
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((_) async => 1);

        final location = UserLocation(
          userId: 'user1',
          latitude: 40.0,
          longitude: -74.0,
          timestamp: '2024-01-01T00:00:00Z',
          iv: validIv,
        );

        expectLater(
          repository.locationUpdates,
          emits(predicate<UserLocation>((l) => l.userId == 'user1')),
        );

        await repository.insertLocation(location);

        verify(() => mockDatabase.insert(
          'UserLocations',
          any(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        )).called(1);
      });
    });

    group('deleteUserLocations', () {
      test('deletes by userId', () async {
        when(() => mockDatabase.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => 1);

        await repository.deleteUserLocations('user1');

        verify(() => mockDatabase.delete(
          'UserLocations',
          where: 'userId = ?',
          whereArgs: ['user1'],
        )).called(1);
      });
    });

    group('deleteUserLocationsIfNotInRooms', () {
      test('returns true and deletes when user has no rooms', () async {
        when(() => mockDatabase.query(
          'UserRelationships',
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => []);

        when(() => mockDatabase.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => 1);

        final result = await repository.deleteUserLocationsIfNotInRooms('user1');
        expect(result, isTrue);

        verify(() => mockDatabase.delete(
          'UserLocations',
          where: 'userId = ?',
          whereArgs: ['user1'],
        )).called(1);
      });

      test('returns false when user still in rooms', () async {
        when(() => mockDatabase.query(
          'UserRelationships',
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => [{'userId': 'user1', 'roomId': 'room1'}]);

        final result = await repository.deleteUserLocationsIfNotInRooms('user1');
        expect(result, isFalse);

        verifyNever(() => mockDatabase.delete(
          'UserLocations',
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ));
      });
    });

    group('getLatestLocation', () {
      test('returns null when no results', () async {
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => []);

        final result = await repository.getLatestLocation('user1');
        expect(result, isNull);
      });
    });

    group('getLatestLocationFromHistory', () {
      test('returns null when no results', () async {
        when(() => mockDatabase.rawQuery(any(), any()))
            .thenAnswer((_) async => []);

        final result = await repository.getLatestLocationFromHistory('user1');
        expect(result, isNull);
      });
    });

    group('getAllLatestLocations', () {
      test('returns empty list when no locations', () async {
        when(() => mockDatabase.rawQuery(any()))
            .thenAnswer((_) async => []);

        final result = await repository.getAllLatestLocations();
        expect(result, isEmpty);
      });
    });

    group('getAllLocations', () {
      test('queries correct table with ordering', () async {
        when(() => mockDatabase.query(
          any(),
          orderBy: any(named: 'orderBy'),
        )).thenAnswer((_) async => []);

        final result = await repository.getAllLocations();
        expect(result, isEmpty);

        verify(() => mockDatabase.query(
          'UserLocations',
          orderBy: 'timestamp DESC',
        )).called(1);
      });
    });
  });
}
