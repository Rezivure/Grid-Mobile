import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/models/room.dart';

class MockDatabaseService extends Mock implements DatabaseService {}
class MockDatabase extends Mock implements Database {}

void main() {
  late RoomRepository repository;
  late MockDatabaseService mockDatabaseService;
  late MockDatabase mockDatabase;

  setUp(() {
    mockDatabase = MockDatabase();
    mockDatabaseService = MockDatabaseService();
    repository = RoomRepository(mockDatabaseService);

    // Mock the database getter
    when(() => mockDatabaseService.database).thenAnswer((_) async => mockDatabase);
    
    // Register fallback values for any() matchers
    registerFallbackValue(<String, dynamic>{});
  });

  group('RoomRepository', () {
    test('insertRoom calls db.insert with correct table and data', () async {
      // Arrange
      final room = Room(
        roomId: 'room1',
        name: 'Test Room',
        isGroup: true,
        lastActivity: '2024-01-01T00:00:00.000Z',
        avatarUrl: 'https://example.com/avatar.png',
        members: ['user1', 'user2'],
        expirationTimestamp: 1234567890,
      );

      when(() => mockDatabase.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.insertRoom(room);

      // Assert
      verify(() => mockDatabase.insert(
        'Rooms',
        room.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      )).called(1);
    });

    test('getAllRooms queries Rooms table and returns Room list', () async {
      // Arrange
      final mockData = [
        {
          'roomId': 'room1',
          'name': 'Room 1',
          'isGroup': 1,
          'lastActivity': '2024-01-01T00:00:00.000Z',
          'avatarUrl': null,
          'members': '["user1", "user2"]',
          'expirationTimestamp': 0,
        },
        {
          'roomId': 'room2',
          'name': 'Room 2',
          'isGroup': 0,
          'lastActivity': '2024-01-02T00:00:00.000Z',
          'avatarUrl': 'https://example.com/avatar.png',
          'members': '["user1"]',
          'expirationTimestamp': 1234567890,
        }
      ];

      when(() => mockDatabase.query('Rooms')).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getAllRooms();

      // Assert
      verify(() => mockDatabase.query('Rooms')).called(1);
      expect(result, hasLength(2));
      expect(result[0].roomId, equals('room1'));
      expect(result[0].name, equals('Room 1'));
      expect(result[0].isGroup, equals(true));
      expect(result[1].roomId, equals('room2'));
      expect(result[1].isGroup, equals(false));
    });

    test('getDirectRooms filters where isGroup=0', () async {
      // Arrange
      final mockData = [
        {
          'roomId': 'room1',
          'name': 'Direct Room',
          'isGroup': 0,
          'lastActivity': '2024-01-01T00:00:00.000Z',
          'avatarUrl': null,
          'members': '["user1", "user2"]',
          'expirationTimestamp': 0,
        }
      ];

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
      )).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getDirectRooms();

      // Assert
      verify(() => mockDatabase.query(
        'Rooms',
        where: 'isGroup = 0',
      )).called(1);
      expect(result, hasLength(1));
      expect(result[0].isGroup, equals(false));
    });

    test('getGroupRooms filters where isGroup=1', () async {
      // Arrange
      final mockData = [
        {
          'roomId': 'room1',
          'name': 'Group Room',
          'isGroup': 1,
          'lastActivity': '2024-01-01T00:00:00.000Z',
          'avatarUrl': null,
          'members': '["user1", "user2", "user3"]',
          'expirationTimestamp': 0,
        }
      ];

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
      )).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getGroupRooms();

      // Assert
      verify(() => mockDatabase.query(
        'Rooms',
        where: 'isGroup = 1',
      )).called(1);
      expect(result, hasLength(1));
      expect(result[0].isGroup, equals(true));
    });

    test('getRoomById queries by roomId and returns Room', () async {
      // Arrange
      final mockData = [
        {
          'roomId': 'room1',
          'name': 'Test Room',
          'isGroup': 1,
          'lastActivity': '2024-01-01T00:00:00.000Z',
          'avatarUrl': null,
          'members': '["user1", "user2"]',
          'expirationTimestamp': 0,
        }
      ];

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getRoomById('room1');

      // Assert
      verify(() => mockDatabase.query(
        'Rooms',
        where: 'roomId = ?',
        whereArgs: ['room1'],
      )).called(1);
      expect(result, isNotNull);
      expect(result!.roomId, equals('room1'));
    });

    test('getRoomById nonexistent returns null', () async {
      // Arrange
      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => []);

      // Act
      final result = await repository.getRoomById('nonexistent');

      // Assert
      verify(() => mockDatabase.query(
        'Rooms',
        where: 'roomId = ?',
        whereArgs: ['nonexistent'],
      )).called(1);
      expect(result, isNull);
    });

    test('insertRoomParticipant inserts into RoomParticipants', () async {
      // Arrange
      when(() => mockDatabase.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.insertRoomParticipant('room1', 'user1');

      // Assert
      verify(() => mockDatabase.insert(
        'RoomParticipants',
        {
          'roomId': 'room1',
          'userId': 'user1',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      )).called(1);
    });

    test('getRoomParticipants returns userId list', () async {
      // Arrange
      final mockData = [
        {'userId': 'user1'},
        {'userId': 'user2'},
        {'userId': 'user3'},
      ];

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getRoomParticipants('room1');

      // Assert
      verify(() => mockDatabase.query(
        'RoomParticipants',
        where: 'roomId = ?',
        whereArgs: ['room1'],
      )).called(1);
      expect(result, equals(['user1', 'user2', 'user3']));
    });

    test('getUserRooms queries by userId', () async {
      // Arrange
      final mockData = [
        {'roomId': 'room1'},
        {'roomId': 'room2'},
      ];

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getUserRooms('user1');

      // Assert
      verify(() => mockDatabase.query(
        'RoomParticipants',
        where: 'userId = ?',
        whereArgs: ['user1'],
      )).called(1);
      expect(result, equals(['room1', 'room2']));
    });

    test('removeRoomParticipant deletes correct row', () async {
      // Arrange
      when(() => mockDatabase.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.removeRoomParticipant('room1', 'user1');

      // Assert
      verify(() => mockDatabase.delete(
        'RoomParticipants',
        where: 'roomId = ? AND userId = ?',
        whereArgs: ['room1', 'user1'],
      )).called(1);
    });

    test('removeAllParticipants deletes by roomId', () async {
      // Arrange
      when(() => mockDatabase.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => 2);

      // Act
      await repository.removeAllParticipants('room1');

      // Assert
      verify(() => mockDatabase.delete(
        'RoomParticipants',
        where: 'roomId = ?',
        whereArgs: ['room1'],
      )).called(1);
    });

    test('deleteRoom deletes by roomId', () async {
      // Arrange
      when(() => mockDatabase.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.deleteRoom('room1');

      // Assert
      verify(() => mockDatabase.delete(
        'Rooms',
        where: 'roomId = ?',
        whereArgs: ['room1'],
      )).called(1);
    });

    test('getExpiredRooms filters by expirationTimestamp', () async {
      // Arrange
      final mockData = [
        {
          'roomId': 'expired1',
          'name': 'Expired Room',
          'isGroup': 1,
          'lastActivity': '2024-01-01T00:00:00.000Z',
          'avatarUrl': null,
          'members': '["user1"]',
          'expirationTimestamp': 1000000, // Old timestamp
        }
      ];

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getExpiredRooms();

      // Assert
      verify(() => mockDatabase.query(
        'Rooms',
        where: 'isGroup = 1 AND expirationTimestamp > 0 AND expirationTimestamp < ?',
        whereArgs: any(named: 'whereArgs'),
      )).called(1);
      expect(result, hasLength(1));
      expect(result[0].roomId, equals('expired1'));
    });

    test('getNonExpiredRooms includes 0 and future timestamps', () async {
      // Arrange
      final mockData = [
        {
          'roomId': 'active1',
          'name': 'Active Room',
          'isGroup': 1,
          'lastActivity': '2024-01-01T00:00:00.000Z',
          'avatarUrl': null,
          'members': '["user1"]',
          'expirationTimestamp': 0, // Never expires
        },
        {
          'roomId': 'future1',
          'name': 'Future Room',
          'isGroup': 1,
          'lastActivity': '2024-01-01T00:00:00.000Z',
          'avatarUrl': null,
          'members': '["user1"]',
          'expirationTimestamp': 9999999999, // Future timestamp
        }
      ];

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getNonExpiredRooms();

      // Assert
      verify(() => mockDatabase.query(
        'Rooms',
        where: 'isGroup = 1 AND (expirationTimestamp = 0 OR expirationTimestamp > ?)',
        whereArgs: any(named: 'whereArgs'),
      )).called(1);
      expect(result, hasLength(2));
    });

    test('updateLastActivity updates correct room', () async {
      // Arrange
      when(() => mockDatabase.update(
        any(),
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.updateLastActivity('room1', '2024-01-01T12:00:00.000Z');

      // Assert
      verify(() => mockDatabase.update(
        'Rooms',
        {'lastActivity': '2024-01-01T12:00:00.000Z'},
        where: 'roomId = ?',
        whereArgs: ['room1'],
      )).called(1);
    });

    test('updateRoom updates correct room', () async {
      // Arrange
      final room = Room(
        roomId: 'room1',
        name: 'Updated Room',
        isGroup: true,
        lastActivity: '2024-01-01T00:00:00.000Z',
        avatarUrl: 'https://example.com/new-avatar.png',
        members: ['user1', 'user2', 'user3'],
        expirationTimestamp: 1234567890,
      );

      when(() => mockDatabase.update(
        any(),
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.updateRoom(room);

      // Assert
      verify(() => mockDatabase.update(
        'Rooms',
        room.toMap(),
        where: 'roomId = ?',
        whereArgs: [room.roomId],
      )).called(1);
    });

    // TODO: Add leaveRoom transaction test once proper mocking is figured out
  });
}