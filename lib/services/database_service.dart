import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';

class DatabaseService {
  static Database? _database;
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Get the database instance (Singleton)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  /// Initialize the database
  Future<Database> initDatabase() async {
    var directory = await getApplicationDocumentsDirectory();
    String path = join(directory.path, 'secure_grid.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await _initializeEncryptionKey();
        await UserRepository.createTable(db);
        await RoomRepository.createTables(db);
        await LocationRepository.createTable(db);
        await SharingPreferencesRepository.createTable(db);
        await UserKeysRepository.createTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _initializeEncryptionKey();
        if (oldVersion < 2) {
          await _migrateToVersion2(db);
        }
        if (oldVersion < 3) {
          await _migrateToVersion3(db);
        }

        if (oldVersion < 4) {
          await _migrateToVersion4(db);
        }

      },
    );
  }

  /// Ensures an encryption key exists in secure storage
  Future<void> _initializeEncryptionKey() async {
    String? key = await _secureStorage.read(key: 'encryptionKey');
    if (key == null) {
      final keyBytes = Key.fromSecureRandom(32);
      key = keyBytes.base64;
      await _secureStorage.write(key: 'encryptionKey', value: key);
      print('Generated new encryption key.');
    } else {
      print('Encryption key exists.');
    }
  }

  /// Fetch the encryption key
  Future<String> getEncryptionKey() async {
    String? key = await _secureStorage.read(key: 'encryptionKey');
    if (key == null) {
      throw Exception('Encryption key not found!');
    }
    return key;
  }

  /// Migration to version 2
  Future<void> _migrateToVersion2(Database db) async {
    print('Migrating to version 2...');
    try {
      await db.execute('ALTER TABLE UserLocations ADD COLUMN accuracy REAL;');
      print('Migration to version 2 complete.');
    } catch (e) {
      print('Error during migration to version 2: $e');
    }
  }

  /// Migration to version 3
  Future<void> _migrateToVersion3(Database db) async {
    print('Migrating to version 3...');
    try {
      await UserKeysRepository.createTable(db);
      print('Migration to version 3 complete.');
    } catch (e) {
      print('Error during migration to version 3: $e');
    }
  }

  Future<void> _migrateToVersion4(Database db) async {
    print('Migrating to version 4...');
    try {
      // Add the approvedKeys column if it doesn't exist
      await db.execute('ALTER TABLE UserKeys ADD COLUMN approvedKeys TEXT DEFAULT \'false\'');
      print('Migration to version 3 complete.');
    } catch (e) {
      print('Error during migration to version 3: $e');
    }
  }


  /// Clear all data from the database
  Future<void> clearAllData() async {
    final db = await database;
    final tables = ['Users', 'UserLocations', 'Rooms', 'SharingPreferences', 'UserKeys'];
    for (final table in tables) {
      await db.delete(table);
    }
  }

  /// Delete and reinitialize the database
  Future<void> deleteAndReinitialize() async {
    print("Deleting database...");
    final dbPath = await getDatabasesPath();
    String path = join(dbPath, 'secure_grid.db');

    await deleteDatabase(path);
    _database = await initDatabase();
    print("Re-initialized db");
  }
}
