import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/services/database_service.dart';

class LocationRepository {
  final DatabaseService _databaseService;
  final StreamController<UserLocation> _locationUpdatesController = StreamController<UserLocation>.broadcast();

  LocationRepository(this._databaseService);

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE UserLocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT,
        latitude TEXT,
        longitude TEXT,
        timestamp TEXT,
        iv TEXT,
        FOREIGN KEY (userId) REFERENCES Users (id)
      );
    ''');
  }

  /// Stream of location updates, emits a UserLocation whenever one is inserted or updated
  Stream<UserLocation> get locationUpdates => _locationUpdatesController.stream;

  /// Insert or update a user's location and notify listeners
  Future<void> insertLocation(UserLocation location) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();
    await db.insert(
      'UserLocations',
      location.toMap(encryptionKey),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Notify that a location was updated
    _locationUpdatesController.add(location);
  }

  /// Delete all location data for a specific user
  Future<void> deleteUserLocations(String userId) async {
    print("Deleting location data for user: $userId");
    final db = await _databaseService.database;

    await db.delete(
      'UserLocations',
      where: 'userId = ?',
      whereArgs: [userId],
    );

    print("Deleted all location data for user: $userId");
  }

  /// Fetch the latest location for a given user
  Future<UserLocation?> getLatestLocation(String userId) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();
    final results = await db.query(
      'UserLocations',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (results.isNotEmpty) {
      return UserLocation.fromMap(results.first, encryptionKey);
    }
    return null;
  }

  /// Fetch all locations for all users
  Future<List<UserLocation>> getAllLocations() async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();
    final results = await db.query(
      'UserLocations',
      orderBy: 'timestamp DESC',
    );
    return results.map((row) => UserLocation.fromMap(row, encryptionKey)).toList();
  }
}
