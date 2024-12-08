import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/user.dart';
import 'package:grid_frontend/services/database_service.dart';

class UserRepository {
  final DatabaseService _databaseService;

  UserRepository(this._databaseService);

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE Users (
        id TEXT PRIMARY KEY,
        displayName TEXT,
        avatarUrl TEXT,
        lastSeen TEXT
      );
    ''');
  }

  Future<void> insertUser(User user) async {
    final db = await _databaseService.database;
    await db.insert('Users', user.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<User>> getAllUsers() async {
    final db = await _databaseService.database;
    final results = await db.query('Users');
    return results.map((map) => User.fromMap(map)).toList();
  }

  Future<User?> getUserById(String userId) async {
    final db = await _databaseService.database;
    final results = await db.query('Users', where: 'id = ?', whereArgs: [userId]);
    if (results.isNotEmpty) {
      return User.fromMap(results.first);
    }
    return null;
  }
}
