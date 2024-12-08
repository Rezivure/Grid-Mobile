import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/grid_user.dart';
import 'package:grid_frontend/services/database_service.dart';

class UserRepository {
  final DatabaseService _databaseService;

  UserRepository(this._databaseService);

  /// Creates the Users table in the database
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE Users (
        id TEXT PRIMARY KEY,
        displayName TEXT,
        avatarUrl TEXT,
        lastSeen TEXT,
        profileStatus TEXT
      );
    ''');
  }

  /// Inserts a GridUser into the database
  Future<void> insertUser(GridUser user) async {
    final db = await _databaseService.database;
    await db.insert(
      'Users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetches all users from the database
  Future<List<GridUser>> getAllUsers() async {
    final db = await _databaseService.database;
    final results = await db.query('Users');
    return results.map((map) => GridUser.fromMap(map)).toList();
  }

  /// Fetches a specific user by their ID
  Future<GridUser?> getUserById(String userId) async {
    final db = await _databaseService.database;
    final results = await db.query(
      'Users',
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (results.isNotEmpty) {
      return GridUser.fromMap(results.first);
    }
    return null;
  }
}
