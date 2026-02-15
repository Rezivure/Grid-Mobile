import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';

class MockDatabaseService extends Mock implements DatabaseService {}
class MockDatabase extends Mock implements Database {}

void main() {
  late SharingPreferencesRepository repository;
  late MockDatabaseService mockDatabaseService;
  late MockDatabase mockDatabase;

  setUp(() {
    mockDatabase = MockDatabase();
    mockDatabaseService = MockDatabaseService();
    repository = SharingPreferencesRepository(mockDatabaseService);

    // Mock the database getter
    when(() => mockDatabaseService.database).thenAnswer((_) async => mockDatabase);
    
    // Register fallback values for any() matchers
    registerFallbackValue(<String, dynamic>{});
  });

  group('SharingPreferencesRepository', () {
    test('setSharingPreferences inserts with replace conflict algorithm', () async {
      // Arrange
      final preferences = SharingPreferences(
        id: 1,
        targetId: 'room1',
        targetType: 'room',
        activeSharing: true,
        shareWindows: null,
      );

      when(() => mockDatabase.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.setSharingPreferences(preferences);

      // Assert
      verify(() => mockDatabase.insert(
        'SharingPreferences',
        preferences.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      )).called(1);
    });

    test('getSharingPreferences queries by targetId and targetType', () async {
      // Arrange
      final mockData = {
        'id': 1,
        'targetId': 'room1',
        'targetType': 'room',
        'activeSharing': 1,
        'sharePeriods': null,
      };

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => [mockData]);

      // Act
      final result = await repository.getSharingPreferences('room1', 'room');

      // Assert
      verify(() => mockDatabase.query(
        'SharingPreferences',
        where: 'targetId = ? AND targetType = ?',
        whereArgs: ['room1', 'room'],
      )).called(1);
      expect(result, isNotNull);
      expect(result!.targetId, equals('room1'));
      expect(result.targetType, equals('room'));
      expect(result.activeSharing, equals(true));
    });

    test('getSharingPreferences returns null when not found', () async {
      // Arrange
      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => []);

      // Act
      final result = await repository.getSharingPreferences('nonexistent', 'room');

      // Assert
      verify(() => mockDatabase.query(
        'SharingPreferences',
        where: 'targetId = ? AND targetType = ?',
        whereArgs: ['nonexistent', 'room'],
      )).called(1);
      expect(result, isNull);
    });

    test('getAllSharingPreferences queries all records', () async {
      // Arrange
      final mockData = [
        {
          'id': 1,
          'targetId': 'room1',
          'targetType': 'room',
          'activeSharing': 1,
          'sharePeriods': null,
        },
        {
          'id': 2,
          'targetId': 'user1',
          'targetType': 'user',
          'activeSharing': 0,
          'sharePeriods': null,
        }
      ];

      when(() => mockDatabase.query('SharingPreferences')).thenAnswer((_) async => mockData);

      // Act
      final result = await repository.getAllSharingPreferences();

      // Assert
      verify(() => mockDatabase.query('SharingPreferences')).called(1);
      expect(result, hasLength(2));
      expect(result[0].targetId, equals('room1'));
      expect(result[0].targetType, equals('room'));
      expect(result[0].activeSharing, equals(true));
      expect(result[1].targetId, equals('user1'));
      expect(result[1].targetType, equals('user'));
      expect(result[1].activeSharing, equals(false));
    });

    test('deleteSharingPreferences deletes by targetId and targetType', () async {
      // Arrange
      when(() => mockDatabase.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.deleteSharingPreferences('room1', 'room');

      // Assert
      verify(() => mockDatabase.delete(
        'SharingPreferences',
        where: 'targetId = ? AND targetType = ?',
        whereArgs: ['room1', 'room'],
      )).called(1);
    });

    test('clearAllSharingPreferences deletes all records', () async {
      // Arrange
      when(() => mockDatabase.delete('SharingPreferences')).thenAnswer((_) async => 5);

      // Act
      await repository.clearAllSharingPreferences();

      // Assert
      verify(() => mockDatabase.delete('SharingPreferences')).called(1);
    });

    test('setSharingPreferences with shareWindows JSON encodes correctly', () async {
      // Arrange - This test checks if the SharingPreferences model handles JSON encoding
      final preferences = SharingPreferences(
        id: 1,
        targetId: 'room1',
        targetType: 'room',
        activeSharing: true,
        shareWindows: [], // Empty list should be encoded as JSON
      );

      when(() => mockDatabase.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      )).thenAnswer((_) async => 1);

      // Act
      await repository.setSharingPreferences(preferences);

      // Assert
      verify(() => mockDatabase.insert(
        'SharingPreferences',
        preferences.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      )).called(1);
    });

    test('getSharingPreferences handles JSON shareWindows', () async {
      // Arrange
      final mockData = {
        'id': 1,
        'targetId': 'room1',
        'targetType': 'room',
        'activeSharing': 1,
        'sharePeriods': '[]', // Empty JSON array
      };

      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => [mockData]);

      // Act
      final result = await repository.getSharingPreferences('room1', 'room');

      // Assert
      expect(result, isNotNull);
      expect(result!.shareWindows, isNotNull);
      expect(result.shareWindows, isEmpty);
    });

    test('CRUD operations work together', () async {
      // This is a higher-level test that verifies the basic CRUD operations work together
      final preferences = SharingPreferences(
        targetId: 'room1',
        targetType: 'room',
        activeSharing: true,
        shareWindows: null,
      );

      // Mock insert (Create)
      when(() => mockDatabase.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      )).thenAnswer((_) async => 1);

      // Mock query (Read)
      when(() => mockDatabase.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => [{
        'id': 1,
        'targetId': 'room1',
        'targetType': 'room',
        'activeSharing': 1,
        'sharePeriods': null,
      }]);

      // Mock delete (Delete)
      when(() => mockDatabase.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      )).thenAnswer((_) async => 1);

      // Test Create
      await repository.setSharingPreferences(preferences);
      
      // Test Read
      final retrieved = await repository.getSharingPreferences('room1', 'room');
      expect(retrieved, isNotNull);
      
      // Test Delete
      await repository.deleteSharingPreferences('room1', 'room');

      // Verify all operations were called
      verify(() => mockDatabase.insert(any(), any(), conflictAlgorithm: any(named: 'conflictAlgorithm'))).called(1);
      verify(() => mockDatabase.query(any(), where: any(named: 'where'), whereArgs: any(named: 'whereArgs'))).called(1);
      verify(() => mockDatabase.delete(any(), where: any(named: 'where'), whereArgs: any(named: 'whereArgs'))).called(1);
    });
  });
}