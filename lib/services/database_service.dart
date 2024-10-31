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
      deviceKeys TEXT,
      iv TEXT
    );
  ''');
    print('UserLocations table created');

    // SharingPreferences DB maps all contacts/group members
    // to a true/false activeSharing which toggles whether you send
    // location updates, approvedKeys which is a bool that gets set to
    // false if keys change, once manually approved in app changes to true
    // and sharePeriods which is a JSON that tracks share windows like
    // 5-7PM Mon-Fri, which can have multiple, etc.

    print('Creating SharingPreferences table');
    await db.execute('''
    CREATE TABLE IF NOT EXISTS SharingPreferences (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId TEXT,
      activeSharing TEXT,       -- true/false as TEXT
      approvedKeys TEXT,        -- true/false as TEXT
      sharePeriods TEXT         -- JSON-encoded string with sharing periods
    );
  ''');
    print('SharingPreferences table created');
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
      String deviceKeysJson,
      ) async {
    final db = await database;
    final encryptionKey = await _getOrCreateEncryptionKey();

    // Generate a random IV for encryption
    final iv = encrypt.IV.fromLength(16);
    final ivString = iv.base64; // Store the IV as a Base64 string

    // Encrypt latitude and longitude
    final encryptedLatitude = _encrypt(latitude.toString(), iv, encryptionKey);
    final encryptedLongitude = _encrypt(longitude.toString(), iv, encryptionKey);

    // Prepare the location map with encrypted values
    final locationData = {
      'userId': userId,
      'latitude': encryptedLatitude,
      'longitude': encryptedLongitude,
      'timestamp': timestamp,
      'deviceKeys': deviceKeysJson, // Already JSON-encoded
      'iv': ivString,
    };

    print('Inserting user location into DB: $locationData');

    await db.insert('UserLocations', locationData, conflictAlgorithm: ConflictAlgorithm.replace);
    _emitLocationUpdates(); // Emit updates to the stream
  }


  Future<List<Map<String, dynamic>>> getUserLocationById(String userId) async {
    final db = await database;
    final encryptionKey = await _getOrCreateEncryptionKey();
    final results = await db.query(
      'UserLocations',
      where: 'userId = ?',
      whereArgs: [userId],
    );

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

  Future<void> updateUserLocation(
      String userId,
      double latitude,
      double longitude,
      String timestamp,
      String deviceKeysJson
      ) async {
    final db = await database;
    final encryptionKey = await _getOrCreateEncryptionKey();

    // Fetch the existing record to retrieve the stored IV
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

    final ivString = existingRecord.first['iv'] as String;
    final iv = encrypt.IV.fromBase64(ivString); // Use the existing IV

    // Encrypt latitude and longitude using the existing IV
    final encryptedLatitude = _encrypt(latitude.toString(), iv, encryptionKey);
    final encryptedLongitude = _encrypt(longitude.toString(), iv, encryptionKey);

    print('Updating user location in DB: UserID: $userId, Latitude: $latitude, Longitude: $longitude, Timestamp: $timestamp, Keys: $deviceKeysJson');

    await db.update(
      'UserLocations',
      {
        'latitude': encryptedLatitude,
        'longitude': encryptedLongitude,
        'timestamp': timestamp,
        'deviceKeys': deviceKeysJson, // Updated device keys JSON
      },
      where: 'userId = ?',
      whereArgs: [userId],
    );
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
      'UserLocations',
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


  void _emitLocationUpdates() async {
    final userLocations = await getUserLocations();
    _locationStreamController.add(userLocations);
  }

  void dispose() {
    _locationStreamController.close(); // Close the stream controller
  }
}