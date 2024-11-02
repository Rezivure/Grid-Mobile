import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'package:grid_frontend/models/sharing_preferences.dart';
import 'package:grid_frontend/models/user_location.dart';


class DatabaseService {
  static Database? _database;
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // StreamController to manage location updates
  final StreamController<List<Map<String, dynamic>>> _locationStreamController =
  StreamController.broadcast();

  Stream<List<Map<String, dynamic>>> get userLocationsStream =>
      _locationStreamController.stream;

  Future<String> _getOrCreateEncryptionKey() async {
    // Try to retrieve the key from secure storage
    String? key = await _secureStorage.read(key: 'encryptionKey');
    if (key == null) {
      // Generate a new random key if it doesn't exist
      final keyBytes = encrypt.Key.fromSecureRandom(32);
      key = keyBytes.base64;
      await _secureStorage.write(key: 'encryptionKey', value: key);
    }
    return key;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    var directory = await getApplicationDocumentsDirectory();
    String path = join(directory.path, 'secure_grid.db');
    return await openDatabase(path, version: 1, onCreate: _createDb);
  }

  void _createDb(Database db, int newVersion) async {

    // UserLocations DB maps all contacts/group members
    // to a location, timestamp, and their most recent list of
    // device keys
    print('Creating UserLocations table');
    await db.execute('''
    CREATE TABLE IF NOT EXISTS UserLocations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId TEXT,
      latitude TEXT,
      longitude TEXT,
      timestamp TEXT,
      iv TEXT
    );
  ''');
    print('UserLocations table created');


    print('Creating SharingPreferences table');
    await db.execute('''
    CREATE TABLE IF NOT EXISTS SharingPreferences (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId TEXT,
      activeSharing TEXT,       -- true/false as TEXT
      sharePeriods TEXT         -- JSON-encoded string with sharing periods
    );
  ''');
    print('SharingPreferences table created');

    print('Creating UserDeviceKeys table');
    await db.execute('''
    CREATE TABLE IF NOT EXISTS UserDeviceKeys (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    userId TEXT,
    deviceKeys TEXT,
    approvedKeys TEXT
    );
    ''');
    print('UserDeviceKeys table created');
  }


  String _encrypt(String text, encrypt.IV iv, String encryptionKey) {
    final key = encrypt.Key.fromBase64(encryptionKey);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final encrypted = encrypter.encrypt(text, iv: iv);
    return encrypted.base64;
  }

  String _decrypt(String encryptedText, String ivString, String encryptionKey) {
    final key = encrypt.Key.fromBase64(encryptionKey);
    final iv = encrypt.IV.fromBase64(ivString);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final decrypted = encrypter.decrypt64(encryptedText, iv: iv);
    return decrypted;
  }

  Future<void> insertUserLocation(
      String userId,
      double latitude,
      double longitude,
      String timestamp,
      ) async {
    final db = await database;
    final encryptionKey = await _getOrCreateEncryptionKey();

    // Generate a random IV for encryption
    final iv = encrypt.IV.fromLength(16).base64;

    // Create a UserLocation instance and convert it to a map for insertion
    final userLocation = UserLocation(
      userId: userId,
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      iv: iv,
    );
    await db.insert(
      'UserLocations',
      userLocation.toMap(encryptionKey),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    print('Inserting user location into DB: $userLocation');
    _emitLocationUpdates(); // Emit updates to the stream
  }

  Future<void> insertSharingPreferences({
    required String userId,
    required bool activeSharing,
    required Map<String, dynamic> sharePeriods, // Define share periods as a map
  }) async {
    final db = await database;

    // Convert share periods to JSON string
    final sharePeriodsJson = jsonEncode(sharePeriods);

    // Prepare data for insertion
    final sharingPreferences = {
      'userId': userId,
      'activeSharing': activeSharing ? 'true' : 'false',
      'sharePeriods': sharePeriodsJson,
    };

    print('Inserting sharing preferences into DB for user: $userId');

    await db.insert(
      'SharingPreferences',
      sharingPreferences,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserLocation?> getUserLocationById(String userId) async {
    final db = await database;
    final encryptionKey = await _getOrCreateEncryptionKey();
    final results = await db.query(
      'UserLocations',
      where: 'userId = ?',
      whereArgs: [userId],
    );

    if (results.isNotEmpty) {
      // Use UserLocation's fromMap constructor to handle decryption
      return UserLocation.fromMap(results.first, encryptionKey);
    }
    return null;
  }

  Future<void> updateUserLocation(
      String userId,
      double latitude,
      double longitude,
      String timestamp,
      ) async {
    final db = await database;
    final encryptionKey = await _getOrCreateEncryptionKey();

    // Retrieve the existing IV for this user
    final existingRecord = await db.query(
      'UserLocations',
      columns: ['iv'],
      where: 'userId = ?',
      whereArgs: [userId],
    );

    if (existingRecord.isEmpty) {
      print('No existing record found for userId $userId');
      return;
    }

    final iv = existingRecord.first['iv'] as String;

    // Create a UserLocation instance and convert it to a map for updating
    final userLocation = UserLocation(
      userId: userId,
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      iv: iv,
    );

    await db.update(
      'UserLocations',
      userLocation.toMap(encryptionKey),
      where: 'userId = ?',
      whereArgs: [userId],
    );

    print('Updating user location in DB: $userLocation');
  }



  void emitUpdatesToAppAfterUpdatingDB() {
    _emitLocationUpdates(); // Emit updates to the stream
  }

  Future<List<Map<String, dynamic>>> getUserLocations() async {
    final db = await database;
    final encryptionKey = await _getOrCreateEncryptionKey();
    final results = await db.query('UserLocations');

    // Decrypt data after fetching it from the database
    return results.map((location) {
      final ivString = location['iv'] as String;
      final encryptedLatitude = location['latitude'] as String;
      final encryptedLongitude = location['longitude'] as String;

      final decryptedLatitude = _decrypt(encryptedLatitude, ivString, encryptionKey);
      final decryptedLongitude = _decrypt(encryptedLongitude, ivString, encryptionKey);

      return {
        'userId': location['userId'],
        'latitude': double.parse(decryptedLatitude),
        'longitude': double.parse(decryptedLongitude),
        'timestamp': location['timestamp'],
      };
    }).toList();
  }

  Future<void> deleteUserLocation(int id) async {
    final db = await database;
    await db.delete('UserLocations', where: 'id = ?', whereArgs: [id]);
    _emitLocationUpdates(); // Emit updates to the stream
  }

  Future<void> updateLocationStatus(int id, String status) async {
    final db = await database;
    await db.update(
        'UserLocations',
        {'status': status},
        where: 'id = ?',
        whereArgs: [id]
    );
  }

  Future<void> clearAllData() async {
    var directory = await getApplicationDocumentsDirectory();
    String path = join(directory.path, 'secure_grid.db');

    // Close the database connection
    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    // Delete the database file
    await deleteDatabase(path);

    // Reinitialize the database
    _database = await initDatabase();

    print("Database cleared and reinitialized with new schema.");
    _emitLocationUpdates(); // Emit updates to the stream
  }

  Future<void> verifyDatabase() async {
    final db = await database;

    // Check if the table exists
    var result = await db.rawQuery('PRAGMA table_info(UserLocations)');
    print('UserLocations table schema: $result');

    // Check if any data is in the table
    result = await db.query('UserLocations');
    print('Current data in UserLocations: $result');
  }

  Future<Map<String, dynamic>?> getDeviceKeysByUserId(String userId) async {
    final db = await database;

    // Query the database for the user location record by userId
    final result = await db.query(
      'UserDeviceKeys',
      columns: ['deviceKeys'],
      where: 'userId = ?',
      whereArgs: [userId],
    );

    if (result.isNotEmpty) {
      // Retrieve and decode the deviceKeys JSON if the record exists
      final deviceKeysJson = result.first['deviceKeys'] as String;
      return jsonDecode(deviceKeysJson) as Map<String, dynamic>;
    }
    // Return null if no record found for the userId
    return null;
  }


  Future<SharingPreferences?> getSharingPrefsForUser(String userId) async {
    final db = await database;
    final results = await db.query(
      'SharingPreferences',
      where: 'userId = ?',
      whereArgs: [userId],
    );

    if (results.isNotEmpty) {
      return SharingPreferences.fromMap(results.first);
    }

    return null; // Return null if no result is found
  }

  Future<bool?> getApprovedKeys(String userId) async {
    final db = await database;
    final result = await db.query(
      'UserDeviceKeys',
      columns: ['approvedKeys'],
      where: 'userId = ?',
      whereArgs: [userId],
    );
    if (result.isNotEmpty) {
      return result.first['approvedKeys']?.toString().toLowerCase() == 'true';
    }
    return null; // Returns null if no record found for userId
  }

  Future<void> updateApprovedKeys(String userId, bool approvedKeys) async {
    final db = await database;
    final keys = await getDeviceKeysByUserId(userId);
    await db.update(
      'UserDeviceKeys',
      {'approvedKeys': approvedKeys.toString()},
      where: 'userId = ?',
      whereArgs: [userId],
    );


  }

  Future<bool> checkIfUserHasSharedPrefs(String userId) async {
    final db = await database;
    final result = await db.query(
      'SharingPreferences',
      columns: ['userId'],
      where: 'userId = ?',
      whereArgs: [userId],
    );
    return result.isNotEmpty;
  }

  Future<bool> checkIfUserHasDeviceKeys(String userId) async {
    final db = await database;
    final result = await db.query(
      'UserDeviceKeys',
      columns: ['userId'],
      where: 'userId = ?',
      whereArgs: [userId],
    );
    return result.isNotEmpty;
  }

  Future<void> insertUserKeys(String userId, Map<String, dynamic> keysMap) async {
    final db = await database;

    // Convert the keys map to a JSON string
    final deviceKeysJson = jsonEncode(keysMap);

    // Check if the record exists
    final result = await db.query(
      'UserDeviceKeys',
      where: 'userId = ?',
      whereArgs: [userId],
    );
    print(result);

    if (result.isNotEmpty) {
      // Update existing record
      await db.update(
        'UserDeviceKeys',
        {
          'deviceKeys': deviceKeysJson,
        },
        where: 'userId = ?',
        whereArgs: [userId],
      );
      print('Updated deviceKeys for userId $userId');
    } else {
      // Insert new record with approvedKeys defaulting to true
      await db.insert(
        'UserDeviceKeys',
        {
          'userId': userId,
          'deviceKeys': deviceKeysJson,
          'approvedKeys': "true", // Default to true when inserting
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('Inserted new deviceKeys and approvedKeys for userId $userId');
    }
  }


  void _emitLocationUpdates() async {
    final userLocations = await getUserLocations();
    _locationStreamController.add(userLocations);
  }

  void dispose() {
    _locationStreamController.close(); // Close the stream controller
  }
}