import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart';
import 'package:grid_frontend/services/secure_storage_provider.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/location_history_repository.dart';
import 'package:grid_frontend/repositories/room_location_history_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';

/// Thrown when the encryption key can't be found under any known
/// accessibility level. Caller (typically main.dart) shows a recovery dialog.
class EncryptionKeyMissingException implements Exception {
  const EncryptionKeyMissingException();
  @override
  String toString() => 'Encryption key not found in keychain.';
}

class DatabaseService {
  static Database? _database;
  final FlutterSecureStorage _secureStorage = SecureStorageProvider.instance();
  // Reads only — items written before Fix A landed under the default
  // WhenUnlocked accessibility and are invisible to [_secureStorage].
  final FlutterSecureStorage _legacyStorage = SecureStorageProvider.legacyInstance();
  // In-memory cache so a transient keychain error doesn't poison every
  // subsequent repo read in this process.
  String? _cachedKey;

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
      version: 4,  // Increment version for new RoomLocationHistory table
      onCreate: (db, version) async {
        await _initializeEncryptionKey();
        await UserRepository.createTables(db);
        await RoomRepository.createTables(db);
        await LocationRepository.createTable(db);
        await LocationHistoryRepository.createTable(db);
        await RoomLocationHistoryRepository.createTable(db);
        await SharingPreferencesRepository.createTable(db);
        await UserKeysRepository.createTable(db);
        await MapIconRepository.createTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await LocationHistoryRepository.createTable(db);
        }
        if (oldVersion < 3) {
          await MapIconRepository.createTable(db);
        }
        if (oldVersion < 4) {
          await RoomLocationHistoryRepository.createTable(db);
        }
      },
    );
  }

  /// Ensures an encryption key exists in secure storage
  Future<void> _initializeEncryptionKey() async {
    String? key = await _readKeyWithFallback();
    if (key == null) {
      final keyBytes = Key.fromSecureRandom(32);
      key = keyBytes.base64;
      await _secureStorage.write(key: 'encryptionKey', value: key);
      print('Generated new encryption key.');
    } else {
      print('Encryption key exists.');
    }
    _cachedKey = key;
  }

  /// Fetch the encryption key
  Future<String> getEncryptionKey() async {
    if (_cachedKey != null) return _cachedKey!;
    final key = await _readKeyWithFallback();
    if (key == null) {
      throw const EncryptionKeyMissingException();
    }
    _cachedKey = key;
    return key;
  }

  /// Returns true iff an encryption key is reachable (under either
  /// accessibility). Side-effect: migrates legacy items to the new
  /// accessibility when found. Safe to call at boot for health checks.
  Future<bool> hasEncryptionKey() async {
    if (_cachedKey != null) return true;
    final key = await _readKeyWithFallback();
    if (key == null) return false;
    _cachedKey = key;
    return true;
  }

  /// Recovery for the worst case: keychain item is genuinely gone (data
  /// corruption, user manually wiped keychain, etc). All encrypted on-disk
  /// data is unreadable — wipe the Grid DB and generate a fresh key.
  /// Matrix client state and credentials are NOT touched.
  Future<void> resetEncryptionForRecovery() async {
    print('Resetting encryption for recovery — Grid DB will be wiped.');
    // Clear any stale legacy item so the next read isn't ambiguous.
    try {
      await _legacyStorage.delete(key: 'encryptionKey');
    } catch (_) {}
    try {
      await _secureStorage.delete(key: 'encryptionKey');
    } catch (_) {}
    _cachedKey = null;
    await deleteAndReinitialize();
  }

  Future<String?> _readKeyWithFallback() async {
    final primary = await _secureStorage.read(key: 'encryptionKey');
    if (primary != null) return primary;
    final legacy = await _legacyStorage.read(key: 'encryptionKey');
    if (legacy == null) return null;
    // Migrate to the new accessibility. Best effort — failure is non-fatal
    // because the next read still finds the legacy item.
    try {
      await _secureStorage.write(key: 'encryptionKey', value: legacy);
      await _legacyStorage.delete(key: 'encryptionKey');
      print('Migrated encryption key from legacy accessibility.');
    } catch (e) {
      print('Encryption key migration write failed (non-fatal): $e');
    }
    return legacy;
  }

  /// Clear all data from the database
  Future<void> clearAllData() async {
    final db = await database;
    final tables = ['Users', 'UserLocations', 'LocationHistory', 'Rooms', 'SharingPreferences', 'UserKeys', 'MapIcons'];
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