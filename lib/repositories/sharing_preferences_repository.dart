import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';
import 'package:grid_frontend/services/database_service.dart';

class SharingPreferencesRepository {
  final DatabaseService _databaseService;

  SharingPreferencesRepository(this._databaseService);

  /// Create the `SharingPreferences` table
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE SharingPreferences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        targetId TEXT NOT NULL,
        targetType TEXT NOT NULL,
        activeSharing INTEGER DEFAULT 1,
        sharePeriods TEXT,
        UNIQUE(targetId, targetType) -- Ensures no duplicate preferences for the same target
      );
    ''');
  }

  /// Insert or update sharing preferences
  Future<void> setSharingPreferences(SharingPreferences preferences) async {
    final db = await _databaseService.database;
    await db.insert(
      'SharingPreferences',
      preferences.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // Replace if exists
    );
  }

  /// Fetch sharing preferences for a specific target
  Future<SharingPreferences?> getSharingPreferences(String targetId, String targetType) async {
    final db = await _databaseService.database;
    final results = await db.query(
      'SharingPreferences',
      where: 'targetId = ? AND targetType = ?',
      whereArgs: [targetId, targetType],
    );
    if (results.isNotEmpty) {
      return SharingPreferences.fromMap(results.first);
    }
    return null; // Return null if no results
  }

  /// Fetch all sharing preferences
  Future<List<SharingPreferences>> getAllSharingPreferences() async {
    final db = await _databaseService.database;
    final results = await db.query('SharingPreferences');
    return results.map((result) => SharingPreferences.fromMap(result)).toList();
  }

  /// Delete sharing preferences for a specific target
  Future<void> deleteSharingPreferences(String targetId, String targetType) async {
    final db = await _databaseService.database;
    await db.delete(
      'SharingPreferences',
      where: 'targetId = ? AND targetType = ?',
      whereArgs: [targetId, targetType],
    );
  }

  /// Clear all sharing preferences (used for resets or testing)
  Future<void> clearAllSharingPreferences() async {
    final db = await _databaseService.database;
    await db.delete('SharingPreferences');
  }
}
