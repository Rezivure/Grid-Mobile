import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/models/grid_user.dart';

class MockDatabaseService extends Mock implements DatabaseService {}
class MockDatabase extends Mock implements Database {}

void main() {
  late UserRepository repository;
  late MockDatabaseService mockDatabaseService;
  late MockDatabase mockDatabase;

  setUp(() {
    mockDatabase = MockDatabase();
    mockDatabaseService = MockDatabaseService();
    repository = UserRepository(mockDatabaseService);

    // Mock the database getter
    when(() => mockDatabaseService.database).thenAnswer((_) async => mockDatabase);
    
    // Register fallback values for any() matchers
    registerFallbackValue(<String, dynamic>{});
  });

  group('UserRepository', () {
    test('insertUser calls db.insert with GridUser.toMap()', () async {
      // Arrange
      final user = GridUser(
        userId: 'user1',
        displayName: 'John Doe',
        avatarUrl: 'https://example.com/avatar.png',
        lastSeen: '2024-01-01T00:00:00.000Z',
        profileStatus: 'Available',
      );

      when(() => mockDatabase.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.insertUser(user);

      // Assert
      verify(() => mockDatabase.insert(
        'Users',
        user.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      )).called(1);
    });

    test('getUserById returns GridUser', () async {
      // Arrange
      final mockData = {
        'userId': 'user1',
        'displayName': 'John Doe',
        'avatarUrl': 'https://example.com/avatar.png',
        'lastSeen': '2024-01-01T00:00:00.000Z',
        'profileStatus': 'Available',
      };

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => [mockData]);

      // Act
      final result = await repository.getUserById('user1');

      // Assert
      verify(() => mockDatabase.query(
        'Users',
        where: 'userId = ?',
        whereArgs: ['user1'],
      )).called(1);
      expect(result, isNotNull);
      expect(result!.userId, equals('user1'));
      expect(result.displayName, equals('John Doe'));
    });

    test('getUserById nonexistent returns null', () async {
      // Arrange
      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => []);

      // Act
      final result = await repository.getUserById('nonexistent');

      // Assert
      verify(() => mockDatabase.query(
        'Users',
        where: 'userId = ?',
        whereArgs: ['nonexistent'],
      )).called(1);
      expect(result, isNull);
    });

    test('getAllUsers returns list', () async {
      // Arrange
      final mockData = [
        {
          'userId': 'user1',
          'displayName': 'John Doe',
          'avatarUrl': null,
          'lastSeen': '2024-01-01T00:00:00.000Z',
          'profileStatus': 'Available',
        },
        {
          'userId': 'user2',
          'displayName': 'Jane Smith',
          'avatarUrl': 'https://example.com/avatar.png',
          'lastSeen': '2024-01-02T00:00:00.000Z',
          'profileStatus': 'Busy',
        }
      ];

      when(() => mockDatabase.query('Users')).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getAllUsers();

      // Assert
      verify(() => mockDatabase.query('Users')).called(1);
      expect(result, hasLength(2));
      expect(result[0].userId, equals('user1'));
      expect(result[1].userId, equals('user2'));
    });

    test('getDirectContacts rawQuery with isDirect=1', () async {
      // Arrange
      final mockData = [
        {
          'userId': 'user1',
          'displayName': 'John Doe',
          'avatarUrl': null,
          'lastSeen': '2024-01-01T00:00:00.000Z',
          'profileStatus': 'Available',
        }
      ];

      when(() => mockDatabase.rawQuery(any())).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getDirectContacts();

      // Assert
      verify(() => mockDatabase.rawQuery('''
    SELECT DISTINCT u.*
    FROM Users u
    JOIN UserRelationships ur ON u.userId = ur.userId
    WHERE ur.isDirect = 1
  ''')).called(1);
      expect(result, hasLength(1));
      expect(result[0].userId, equals('user1'));
    });

    test('getGroupParticipants rawQuery with isDirect=0', () async {
      // Arrange
      final mockData = [
        {
          'userId': 'user1',
          'displayName': 'John Doe',
          'avatarUrl': null,
          'lastSeen': '2024-01-01T00:00:00.000Z',
          'profileStatus': 'Available',
        }
      ];

      when(() => mockDatabase.rawQuery(any())).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getGroupParticipants();

      // Assert
      verify(() => mockDatabase.rawQuery('''
    SELECT DISTINCT u.*
    FROM Users u
    JOIN UserRelationships ur ON u.userId = ur.userId
    WHERE ur.isDirect = 0
  ''')).called(1);
      expect(result, hasLength(1));
      expect(result[0].userId, equals('user1'));
    });

    test('insertUserRelationship new relationship inserted', () async {
      // Arrange
      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => []); // No existing relationship

      when(() => mockDatabase.insert(any(), any())).thenAnswer((_) async => 1);

      // Act
      await repository.insertUserRelationship('user1', 'room1', true);

      // Assert
      verify(() => mockDatabase.query(
        'UserRelationships',
        where: 'userId = ? AND roomId = ?',
        whereArgs: ['user1', 'room1'],
      )).called(1);
      verify(() => mockDatabase.insert(
        'UserRelationships',
        {
          'userId': 'user1',
          'roomId': 'room1',
          'isDirect': 1,
          'membershipStatus': null,
        },
      )).called(1);
    });

    test('insertUserRelationship existing updates', () async {
      // Arrange
      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => [
        {'id': 1, 'userId': 'user1', 'roomId': 'room1'}
      ]); // Existing relationship

      when(() => mockDatabase.update(
        any(),
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.insertUserRelationship('user1', 'room1', false, membershipStatus: 'joined');

      // Assert
      verify(() => mockDatabase.update(
        'UserRelationships',
        {
          'isDirect': 0,
          'membershipStatus': 'joined',
        },
        where: 'userId = ? AND roomId = ?',
        whereArgs: ['user1', 'room1'],
      )).called(1);
    });

    test('updateMembershipStatus updates correct row', () async {
      // Arrange
      when(() => mockDatabase.update(
        any(),
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.updateMembershipStatus('user1', 'room1', 'joined');

      // Assert
      verify(() => mockDatabase.update(
        'UserRelationships',
        {'membershipStatus': 'joined'},
        where: 'userId = ? AND roomId = ?',
        whereArgs: ['user1', 'room1'],
      )).called(1);
    });

    test('getUserRooms returns roomId list', () async {
      // Arrange
      final mockData = [
        {'roomId': 'room1'},
        {'roomId': 'room2'},
      ];

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
        columns: any(named: 'columns'),
      )).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getUserRooms('user1');

      // Assert
      verify(() => mockDatabase.query(
        'UserRelationships',
        where: 'userId = ?',
        whereArgs: ['user1'],
        columns: ['roomId'],
      )).called(1);
      expect(result, equals(['room1', 'room2']));
    });

    test('getDirectRoomForContact returns roomId', () async {
      // Arrange
      final mockData = [
        {'roomId': 'room1'},
      ];

      when(() => mockDatabase.rawQuery(any(), any())).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getDirectRoomForContact('user1');

      // Assert
      verify(() => mockDatabase.rawQuery('''
    SELECT roomId 
    FROM UserRelationships 
    WHERE userId = ? AND isDirect = 1
    LIMIT 1
  ''', ['user1'])).called(1);
      expect(result, equals('room1'));
    });

    test('getDirectRoomForContact none returns null', () async {
      // Arrange
      when(() => mockDatabase.rawQuery(any(), any())).thenAnswer((_) async => []);

      // Act
      final result = await repository.getDirectRoomForContact('user1');

      // Assert
      verify(() => mockDatabase.rawQuery('''
    SELECT roomId 
    FROM UserRelationships 
    WHERE userId = ? AND isDirect = 1
    LIMIT 1
  ''', ['user1'])).called(1);
      expect(result, isNull);
    });

    // TODO: Add deleteUser and removeContact transaction tests once proper mocking is figured out
  });
}