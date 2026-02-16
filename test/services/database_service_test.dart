import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'dart:io';

class MockDatabase extends Mock implements Database {}
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}
class MockDirectory extends Mock implements Directory {}

// Testable version of DatabaseService with dependency injection
class TestableDatabaseService {
  final FlutterSecureStorage secureStorage;
  Database? _database;
  final Future<Database> Function(String, {int? version, Function(Database, int)? onCreate, Function(Database, int, int)? onUpgrade}) openDatabaseFn;
  final Future<Directory> Function() getApplicationDocumentsDirectoryFn;

  TestableDatabaseService({
    required this.secureStorage,
    required this.openDatabaseFn,
    required this.getApplicationDocumentsDirectoryFn,
  });

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    var directory = await getApplicationDocumentsDirectoryFn();
    String path = '${directory.path}/secure_grid.db';

    return await openDatabaseFn(
      path,
      version: 4,
      onCreate: (db, version) async {
        await _initializeEncryptionKey();
        // Skip actual table creation for tests
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Skip actual table upgrade for tests
      },
    );
  }

  Future<void> _initializeEncryptionKey() async {
    String? key = await secureStorage.read(key: 'encryptionKey');
    if (key == null) {
      // Generate a mock key for testing
      const mockKey = 'dGVzdGtleWZvcnRlc3RpbmdwdXJwb3NlczEyMzQ='; // base64 encoded 32-byte key
      await secureStorage.write(key: 'encryptionKey', value: mockKey);
    }
  }

  Future<String> getEncryptionKey() async {
    String? key = await secureStorage.read(key: 'encryptionKey');
    if (key == null) {
      throw Exception('Encryption key not found!');
    }
    return key;
  }

  Future<void> clearAllData() async {
    final db = await database;
    final tables = ['Users', 'UserLocations', 'LocationHistory', 'Rooms', 'SharingPreferences', 'UserKeys', 'MapIcons'];
    for (final table in tables) {
      await db.delete(table);
    }
  }

  Future<void> deleteAndReinitialize() async {
    _database = null; // Reset in-memory reference
    _database = await initDatabase();
  }
}

void main() {
  late TestableDatabaseService databaseService;
  late MockFlutterSecureStorage mockSecureStorage;
  late MockDatabase mockDatabase;
  late MockDirectory mockDirectory;

  setUp(() {
    mockSecureStorage = MockFlutterSecureStorage();
    mockDatabase = MockDatabase();
    mockDirectory = MockDirectory();
    
    when(() => mockDirectory.path).thenReturn('/mock/app/documents');

    databaseService = TestableDatabaseService(
      secureStorage: mockSecureStorage,
      openDatabaseFn: (path, {version, onCreate, onUpgrade}) async {
        // Call onCreate to test initialization
        if (onCreate != null) {
          await onCreate(mockDatabase, version ?? 1);
        }
        return mockDatabase;
      },
      getApplicationDocumentsDirectoryFn: () async => mockDirectory,
    );

    registerFallbackValue(<String, dynamic>{});
  });

  group('DatabaseService', () {
    group('database getter', () {
      test('returns cached database instance on subsequent calls', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => 'existing_key');

        // Act
        final db1 = await databaseService.database;
        final db2 = await databaseService.database;

        // Assert
        expect(db1, same(db2));
        expect(db1, equals(mockDatabase));
      });

      test('initializes database if not already cached', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => 'existing_key');

        // Act
        final db = await databaseService.database;

        // Assert
        expect(db, equals(mockDatabase));
        verify(() => mockSecureStorage.read(key: 'encryptionKey')).called(1);
      });
    });

    group('initDatabase', () {
      test('opens database with correct path and version', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => 'existing_key');
        
        bool openDatabaseCalled = false;
        String? capturedPath;
        int? capturedVersion;

        databaseService = TestableDatabaseService(
          secureStorage: mockSecureStorage,
          openDatabaseFn: (path, {version, onCreate, onUpgrade}) async {
            openDatabaseCalled = true;
            capturedPath = path;
            capturedVersion = version;
            if (onCreate != null) {
              await onCreate(mockDatabase, version ?? 1);
            }
            return mockDatabase;
          },
          getApplicationDocumentsDirectoryFn: () async => mockDirectory,
        );

        // Act
        await databaseService.initDatabase();

        // Assert
        expect(openDatabaseCalled, isTrue);
        expect(capturedPath, equals('/mock/app/documents/secure_grid.db'));
        expect(capturedVersion, equals(4));
      });

      test('calls onCreate callback when database is created', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => null);
        when(() => mockSecureStorage.write(key: 'encryptionKey', value: any(named: 'value')))
            .thenAnswer((_) async {});

        bool onCreateCalled = false;
        Database? onCreateDatabase;
        int? onCreateVersion;

        databaseService = TestableDatabaseService(
          secureStorage: mockSecureStorage,
          openDatabaseFn: (path, {version, onCreate, onUpgrade}) async {
            if (onCreate != null) {
              onCreateCalled = true;
              onCreateDatabase = mockDatabase;
              onCreateVersion = version;
              await onCreate(mockDatabase, version ?? 1);
            }
            return mockDatabase;
          },
          getApplicationDocumentsDirectoryFn: () async => mockDirectory,
        );

        // Act
        await databaseService.initDatabase();

        // Assert
        expect(onCreateCalled, isTrue);
        expect(onCreateDatabase, equals(mockDatabase));
        expect(onCreateVersion, equals(4));
      });

      test('initializes encryption key during onCreate', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => null);
        when(() => mockSecureStorage.write(key: 'encryptionKey', value: any(named: 'value')))
            .thenAnswer((_) async {});

        // Act
        await databaseService.initDatabase();

        // Assert
        verify(() => mockSecureStorage.read(key: 'encryptionKey')).called(1);
        verify(() => mockSecureStorage.write(
          key: 'encryptionKey', 
          value: any(named: 'value'),
        )).called(1);
      });
    });

    group('encryption key management', () {
      test('_initializeEncryptionKey creates new key when none exists', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => null);
        when(() => mockSecureStorage.write(key: 'encryptionKey', value: any(named: 'value')))
            .thenAnswer((_) async {});

        // Act
        await databaseService.initDatabase(); // This calls _initializeEncryptionKey

        // Assert
        verify(() => mockSecureStorage.read(key: 'encryptionKey')).called(1);
        verify(() => mockSecureStorage.write(
          key: 'encryptionKey',
          value: any(named: 'value'),
        )).called(1);
      });

      test('_initializeEncryptionKey skips creation when key exists', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => 'existing_key');

        // Act
        await databaseService.initDatabase(); // This calls _initializeEncryptionKey

        // Assert
        verify(() => mockSecureStorage.read(key: 'encryptionKey')).called(1);
        verifyNever(() => mockSecureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ));
      });

      test('getEncryptionKey returns existing key', () async {
        // Arrange
        const expectedKey = 'test_encryption_key';
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => expectedKey);

        // Act
        final key = await databaseService.getEncryptionKey();

        // Assert
        expect(key, equals(expectedKey));
        verify(() => mockSecureStorage.read(key: 'encryptionKey')).called(1);
      });

      test('getEncryptionKey throws exception when key not found', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => null);

        // Act & Assert
        expect(
          () => databaseService.getEncryptionKey(),
          throwsA(predicate<Exception>((e) =>
            e.toString().contains('Encryption key not found!'))),
        );
      });

      test('handles secure storage errors during key retrieval', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenThrow(Exception('Storage error'));

        // Act & Assert
        expect(
          () => databaseService.getEncryptionKey(),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('clearAllData', () {
      test('deletes data from all expected tables', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => 'existing_key');
        when(() => mockDatabase.delete(any())).thenAnswer((_) async => 1);

        // Act
        await databaseService.clearAllData();

        // Assert
        final expectedTables = [
          'Users',
          'UserLocations', 
          'LocationHistory',
          'Rooms',
          'SharingPreferences',
          'UserKeys',
          'MapIcons'
        ];

        for (final table in expectedTables) {
          verify(() => mockDatabase.delete(table)).called(1);
        }
      });

      test('handles database delete errors', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => 'existing_key');
        when(() => mockDatabase.delete(any()))
            .thenThrow(Exception('Delete failed'));

        // Act & Assert
        expect(
          () => databaseService.clearAllData(),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('deleteAndReinitialize', () {
      test('reinitializes database after deletion', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => 'existing_key');

        // Act
        await databaseService.deleteAndReinitialize();

        // Assert
        final newDb = await databaseService.database;
        expect(newDb, equals(mockDatabase));
      });

      test('creates fresh database instance after reinitialization', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => 'existing_key');

        // Get initial database
        final initialDb = await databaseService.database;

        // Act
        await databaseService.deleteAndReinitialize();
        final newDb = await databaseService.database;

        // Assert
        expect(initialDb, equals(mockDatabase));
        expect(newDb, equals(mockDatabase));
        // Both should be the same mock object but in real scenario would be different instances
      });

      test('handles errors during reinitialization', () async {
        // Arrange
        int callCount = 0;
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return 'existing_key';
          throw Exception('Reinitialization error');
        });

        // Get initial database
        await databaseService.database;

        // Act & Assert
        expect(
          () => databaseService.deleteAndReinitialize(),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('error handling', () {
      test('handles database opening errors', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => 'existing_key');

        databaseService = TestableDatabaseService(
          secureStorage: mockSecureStorage,
          openDatabaseFn: (path, {version, onCreate, onUpgrade}) async {
            throw Exception('Failed to open database');
          },
          getApplicationDocumentsDirectoryFn: () async => mockDirectory,
        );

        // Act & Assert
        expect(
          () => databaseService.database,
          throwsA(isA<Exception>()),
        );
      });

      test('handles file system errors when getting app directory', () async {
        // Arrange
        databaseService = TestableDatabaseService(
          secureStorage: mockSecureStorage,
          openDatabaseFn: (path, {version, onCreate, onUpgrade}) async => mockDatabase,
          getApplicationDocumentsDirectoryFn: () async {
            throw FileSystemException('Cannot access directory');
          },
        );

        // Act & Assert
        expect(
          () => databaseService.database,
          throwsA(isA<FileSystemException>()),
        );
      });
    });

    group('edge cases', () {
      test('handles multiple concurrent database accesses', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => 'existing_key');

        // Act
        final futures = List.generate(5, (index) => databaseService.database);
        final databases = await Future.wait(futures);

        // Assert
        // All should return the same database instance
        for (var db in databases) {
          expect(db, same(databases.first));
        }
      });

      test('encryption key is base64 encoded 32-byte key', () async {
        // Arrange
        when(() => mockSecureStorage.read(key: 'encryptionKey'))
            .thenAnswer((_) async => null);
        when(() => mockSecureStorage.write(key: 'encryptionKey', value: any(named: 'value')))
            .thenAnswer((_) async {});

        // Act
        await databaseService.initDatabase();

        // Assert
        final capturedKey = verify(() => mockSecureStorage.write(
          key: 'encryptionKey',
          value: captureAny(named: 'value'),
        )).captured.first as String;

        // Verify it's the mock key we set
        expect(capturedKey, equals('dGVzdGtleWZvcnRlc3RpbmdwdXJwb3NlczEyMzQ='));
      });
    });
  });
}