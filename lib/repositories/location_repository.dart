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
      FOREIGN KEY (userId) REFERENCES Users (id),
      UNIQUE(userId) ON CONFLICT REPLACE
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

  /// Delete location data for a user, but only if they're not in any other rooms
  // In LocationRepository
  Future<bool> deleteUserLocationsIfNotInRooms(String userId) async {
    print("Checking if we should delete location data for user: $userId");
    final db = await _databaseService.database;

    final otherRooms = await db.query(
      'UserRelationships',
      where: 'userId = ?',
      whereArgs: [userId],
    );

    if (otherRooms.isEmpty) {
      print("User $userId not in any rooms, deleting location data");
      await db.delete(
        'UserLocations',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      print("Deleted all location data for user: $userId");
      return true;  // Return true if we deleted
    } else {
      print("User $userId still in ${otherRooms.length} rooms, keeping location data");
      return false;  // Return false if we kept the data
    }
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

  Future<UserLocation?> getLatestLocationFromHistory(String userId) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();

    // Modified query to handle ISO8601 timestamps correctly
    final results = await db.rawQuery('''
      SELECT * FROM UserLocations 
      WHERE userId = ? 
      ORDER BY strftime('%s', timestamp) DESC 
      LIMIT 1
    ''', [userId]);

    if (results.isNotEmpty) {
      return UserLocation.fromMap(results.first, encryptionKey);
    }
    return null;
  }

  Future<List<UserLocation>> getAllLatestLocations() async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();

    // Modified query to handle ISO8601 timestamps correctly
    final results = await db.rawQuery('''
      SELECT l.* FROM UserLocations l
      INNER JOIN (
        SELECT userId, MAX(strftime('%s', timestamp)) as maxTime
        FROM UserLocations
        GROUP BY userId
      ) latest ON l.userId = latest.userId 
      AND strftime('%s', l.timestamp) = latest.maxTime
    ''');

    return results.map((row) => UserLocation.fromMap(row, encryptionKey)).toList();
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
