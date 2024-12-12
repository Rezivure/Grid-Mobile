import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/grid_user.dart';
import 'package:grid_frontend/services/database_service.dart';

class UserRepository {
  final DatabaseService _databaseService;

  UserRepository(this._databaseService);

  /// Creates the Users and UserRelationships tables
  static Future<void> createTables(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS Users (
      userId TEXT PRIMARY KEY, -- Match the column name used in your app
      displayName TEXT,
      avatarUrl TEXT,
      lastSeen TEXT,
      profileStatus TEXT
    );
  ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS UserRelationships (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId TEXT,
      roomId TEXT,
      isDirect INTEGER, -- 1 for direct contact, 0 for group participant
      FOREIGN KEY (userId) REFERENCES Users (userId),
      FOREIGN KEY (roomId) REFERENCES Rooms (roomId)
    );
  ''');
    }


    /// Inserts or updates a user
  Future<void> insertUser(GridUser user) async {
    final db = await _databaseService.database;
    await db.insert(
      'Users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Links a user to a room with relationship type
  Future<void> insertUserRelationship(String userId, String roomId, bool isDirect) async {
    final db = await _databaseService.database;
    await db.insert(
      'UserRelationships',
      {
        'userId': userId,
        'roomId': roomId,
        'isDirect': isDirect ? 1 : 0,
      },
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

  Future<List<GridUser>> getDirectContacts() async {
    final db = await _databaseService.database;

    // query for direct contacts
    final results = await db.rawQuery('''
    SELECT DISTINCT u.*
    FROM Users u
    JOIN UserRelationships ur ON u.userId = ur.userId
    WHERE ur.isDirect = 1
  ''');
    return results.map((map) => GridUser.fromMap(map)).toList();
  }




  /// Fetches all group participants
  Future<List<GridUser>> getGroupParticipants() async {
    final db = await _databaseService.database;
    final results = await db.rawQuery('''
      SELECT DISTINCT u.*
      FROM Users u
      JOIN UserRelationships ur ON u.id = ur.userId
      WHERE ur.isDirect = 0
    ''');
    return results.map((map) => GridUser.fromMap(map)).toList();
  }

  /// Deletes a user relationship (e.g., if a user leaves a room)
  Future<void> deleteUserRelationship(String userId, String roomId) async {
    final db = await _databaseService.database;
    await db.delete(
      'UserRelationships',
      where: 'userId = ? AND roomId = ?',
      whereArgs: [userId, roomId],
    );
  }

  /// Deletes a user from the database
  Future<void> deleteUser(String userId) async {
    final db = await _databaseService.database;
    await db.delete(
      'Users',
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Fetches all rooms associated with a user
  Future<List<String>> getUserRooms(String userId) async {
    final db = await _databaseService.database;
    final results = await db.query(
      'UserRelationships',
      where: 'userId = ?',
      whereArgs: [userId],
      columns: ['roomId'],
    );
    return results.map((map) => map['roomId'] as String).toList();
  }

  Future<void> removeContact(String contactUserId) async {
    final db = await _databaseService.database;

    // Start a transaction to ensure all operations complete together
    await db.transaction((txn) async {
      // First, find the direct room ID for this contact
      final roomResults = await txn.rawQuery('''
        SELECT roomId 
        FROM UserRelationships 
        WHERE userId = ? AND isDirect = 1
      ''', [contactUserId]);

      if (roomResults.isNotEmpty) {
        String roomId = roomResults.first['roomId'] as String;

        // Delete the user relationships
        await txn.delete(
          'UserRelationships',
          where: 'roomId = ?',
          whereArgs: [roomId],
        );

        // Delete the room
        await txn.delete(
          'Rooms',
          where: 'roomId = ?',
          whereArgs: [roomId],
        );

        // Optionally, delete the user if they're not part of any other rooms
        final otherRooms = await txn.query(
          'UserRelationships',
          where: 'userId = ?',
          whereArgs: [contactUserId],
        );

        if (otherRooms.isEmpty) {
          await txn.delete(
            'Users',
            where: 'userId = ?',
            whereArgs: [contactUserId],
          );
        }
      }
    });
  }

  Future<String?> getDirectRoomForContact(String contactUserId) async {
    final db = await _databaseService.database;

    final results = await db.rawQuery('''
    SELECT roomId 
    FROM UserRelationships 
    WHERE userId = ? AND isDirect = 1
    LIMIT 1
  ''', [contactUserId]);

    if (results.isNotEmpty) {
      return results.first['roomId'] as String;
    }

    return null;
  }
}
