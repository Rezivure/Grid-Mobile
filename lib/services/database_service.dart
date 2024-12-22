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
      version: 1,  // Reset to version 1 since we don't need migrations
      onCreate: (db, version) async {
        await _initializeEncryptionKey();
        await UserRepository.createTables(db);
        await RoomRepository.createTables(db);
        await LocationRepository.createTable(db);
        await SharingPreferencesRepository.createTable(db);
        await UserKeysRepository.createTable(db);
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