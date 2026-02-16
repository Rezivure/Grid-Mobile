import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/models/map_icon.dart';

class MockDatabaseService extends Mock implements DatabaseService {}
class MockDatabase extends Mock implements Database {}

MapIcon _makeIcon({
  String id = 'icon1',
  String roomId = 'room1',
  String creatorId = 'user1',
  double lat = 40.0,
  double lng = -74.0,
  Map<String, dynamic>? metadata,
}) {
  return MapIcon(
    id: id,
    roomId: roomId,
    creatorId: creatorId,
    latitude: lat,
    longitude: lng,
    iconType: 'icon',
    iconData: 'pin',
    name: 'Test Icon',
    description: 'A test icon',
    createdAt: DateTime(2024, 1, 1),
    metadata: metadata,
  );
}

void main() {
  late MapIconRepository repository;
  late MockDatabaseService mockDatabaseService;
  late MockDatabase mockDatabase;

  setUp(() {
    mockDatabase = MockDatabase();
    mockDatabaseService = MockDatabaseService();
    repository = MapIconRepository(mockDatabaseService);

    when(() => mockDatabaseService.database).thenAnswer((_) async => mockDatabase);
    registerFallbackValue(<String, dynamic>{});
  });

  group('MapIconRepository', () {
    group('insertMapIcon', () {
      test('inserts icon with replace conflict algorithm', () async {
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((_) async => 1);

        await repository.insertMapIcon(_makeIcon());

        verify(() => mockDatabase.insert(
          'MapIcons',
          any(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        )).called(1);
      });

      test('encodes metadata to JSON string', () async {
        Map<String, dynamic>? capturedData;
        when(() => mockDatabase.insert(
          any(),
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        )).thenAnswer((invocation) async {
          capturedData = invocation.positionalArguments[1] as Map<String, dynamic>;
          return 1;
        });

        await repository.insertMapIcon(_makeIcon(metadata: {'color': 'red'}));

        expect(capturedData, isNotNull);
        // metadata should be JSON-encoded
        expect(capturedData!['metadata'], isA<String>());
      });
    });

    group('getIconsForRoom', () {
      test('queries by room_id and returns parsed icons', () async {
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
          orderBy: any(named: 'orderBy'),
        )).thenAnswer((_) async => [
          {
            'id': 'icon1',
            'room_id': 'room1',
            'creator_id': 'user1',
            'latitude': 40.0,
            'longitude': -74.0,
            'icon_type': 'icon',
            'icon_data': 'pin',
            'name': 'Test',
            'description': null,
            'created_at': '2024-01-01T00:00:00.000',
            'expires_at': null,
            'metadata': null,
          }
        ]);

        final result = await repository.getIconsForRoom('room1');
        expect(result.length, 1);
        expect(result.first.id, 'icon1');
        expect(result.first.roomId, 'room1');

        verify(() => mockDatabase.query(
          'MapIcons',
          where: 'room_id = ?',
          whereArgs: ['room1'],
          orderBy: 'created_at DESC',
        )).called(1);
      });

      test('returns empty list for room with no icons', () async {
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
          orderBy: any(named: 'orderBy'),
        )).thenAnswer((_) async => []);

        final result = await repository.getIconsForRoom('empty_room');
        expect(result, isEmpty);
      });

      test('parses metadata JSON string', () async {
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
          orderBy: any(named: 'orderBy'),
        )).thenAnswer((_) async => [
          {
            'id': 'icon1',
            'room_id': 'room1',
            'creator_id': 'user1',
            'latitude': 40.0,
            'longitude': -74.0,
            'icon_type': 'icon',
            'icon_data': 'pin',
            'name': null,
            'description': null,
            'created_at': '2024-01-01T00:00:00.000',
            'expires_at': null,
            'metadata': '{"color":"red"}',
          }
        ]);

        final result = await repository.getIconsForRoom('room1');
        expect(result.first.metadata, isNotNull);
        expect(result.first.metadata!['color'], 'red');
      });
    });

    group('getIconsForRooms', () {
      test('returns empty list for empty roomIds', () async {
        final result = await repository.getIconsForRooms([]);
        expect(result, isEmpty);
        verifyNever(() => mockDatabase.rawQuery(any(), any()));
      });

      test('queries multiple rooms', () async {
        when(() => mockDatabase.rawQuery(any(), any()))
            .thenAnswer((_) async => [
          {
            'id': 'i1',
            'room_id': 'room1',
            'creator_id': 'user1',
            'latitude': 40.0,
            'longitude': -74.0,
            'icon_type': 'icon',
            'icon_data': 'pin',
            'name': null,
            'description': null,
            'created_at': '2024-01-01T00:00:00.000',
            'expires_at': null,
            'metadata': null,
          },
        ]);

        final result = await repository.getIconsForRooms(['room1', 'room2']);
        expect(result.length, 1);
      });
    });

    group('deleteMapIcon', () {
      test('deletes by id', () async {
        when(() => mockDatabase.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => 1);

        await repository.deleteMapIcon('icon1');

        verify(() => mockDatabase.delete(
          'MapIcons',
          where: 'id = ?',
          whereArgs: ['icon1'],
        )).called(1);
      });
    });

    group('deleteIconsForRoom', () {
      test('deletes all icons for a room', () async {
        when(() => mockDatabase.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => 3);

        await repository.deleteIconsForRoom('room1');

        verify(() => mockDatabase.delete(
          'MapIcons',
          where: 'room_id = ?',
          whereArgs: ['room1'],
        )).called(1);
      });
    });

    group('deleteExpiredIcons', () {
      test('deletes expired icons', () async {
        when(() => mockDatabase.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => 2);

        await repository.deleteExpiredIcons();

        verify(() => mockDatabase.delete(
          'MapIcons',
          where: 'expires_at IS NOT NULL AND expires_at <= ?',
          whereArgs: any(named: 'whereArgs'),
        )).called(1);
      });
    });

    group('updateMapIcon', () {
      test('updates icon by id', () async {
        when(() => mockDatabase.update(
          any(),
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        )).thenAnswer((_) async => 1);

        await repository.updateMapIcon(_makeIcon());

        verify(() => mockDatabase.update(
          'MapIcons',
          any(),
          where: 'id = ?',
          whereArgs: ['icon1'],
        )).called(1);
      });
    });

    group('getActiveIcons', () {
      test('queries non-expired icons', () async {
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
          orderBy: any(named: 'orderBy'),
        )).thenAnswer((_) async => []);

        final result = await repository.getActiveIcons();
        expect(result, isEmpty);

        verify(() => mockDatabase.query(
          'MapIcons',
          where: 'expires_at IS NULL OR expires_at > ?',
          whereArgs: any(named: 'whereArgs'),
          orderBy: 'created_at DESC',
        )).called(1);
      });
    });

    group('getIconsByCreator', () {
      test('queries by creator_id', () async {
        when(() => mockDatabase.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
          orderBy: any(named: 'orderBy'),
        )).thenAnswer((_) async => []);

        final result = await repository.getIconsByCreator('user1');
        expect(result, isEmpty);

        verify(() => mockDatabase.query(
          'MapIcons',
          where: 'creator_id = ?',
          whereArgs: ['user1'],
          orderBy: 'created_at DESC',
        )).called(1);
      });
    });
  });
}
