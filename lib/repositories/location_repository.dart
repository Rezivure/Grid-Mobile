import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/services/database_service.dart';

class LocationRepository {
  final DatabaseService _databaseService;

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

  Future<void> insertLocation(UserLocation location) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();
    await db.insert(
      'UserLocations',
      location.toMap(encryptionKey),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserLocation?> getLatestLocation(String userId) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey(); // Fetch the encryption key
    final results = await db.query(
      'UserLocations',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (results.isNotEmpty) {
      return UserLocation.fromMap(results.first, encryptionKey); // Pass the encryption key
    }
    return null;
  }
}
