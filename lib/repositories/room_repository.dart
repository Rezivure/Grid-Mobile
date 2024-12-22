import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/services/database_service.dart';

class RoomRepository {
  final DatabaseService _databaseService;

  RoomRepository(this._databaseService);

  /// Create the necessary tables for Rooms and RoomParticipants
  static Future<void> createTables(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS Rooms (
      roomId TEXT PRIMARY KEY, -- Ensure column matches your model
      name TEXT,
      isGroup INTEGER,
      lastActivity TEXT,
      avatarUrl TEXT,
      members TEXT, -- JSON-encoded list of members
      expirationTimestamp INTEGER
    );
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS RoomParticipants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      roomId TEXT,
      userId TEXT,
      FOREIGN KEY (roomId) REFERENCES Rooms (roomId) ON DELETE CASCADE,
      FOREIGN KEY (userId) REFERENCES Users (id) ON DELETE CASCADE
    );
    ''');
  }

  /// Insert or update a Room in the database
  Future<void> insertRoom(Room room) async {
    final db = await _databaseService.database;
    await db.insert(
      'Rooms',
      room.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all Rooms from the database
  Future<List<Room>> getAllRooms() async {
    final db = await _databaseService.database;
    final results = await db.query('Rooms');
    return results.map((map) => Room.fromMap(map)).toList();
  }

  /// Insert a participant into a room
  Future<void> insertRoomParticipant(String roomId, String userId) async {
    final db = await _databaseService.database;
    await db.insert(
      'RoomParticipants',
      {
        'roomId': roomId,
        'userId': userId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all participants of a room
  Future<List<String>> getRoomParticipants(String roomId) async {
    final db = await _databaseService.database;
    final results = await db.query(
      'RoomParticipants',
      where: 'roomId = ?',
      whereArgs: [roomId],
    );
    return results.map((map) => map['userId'] as String).toList();
  }

  /// Get all Rooms for a specific user
  Future<List<String>> getUserRooms(String userId) async {
    final db = await _databaseService.database;
    final results = await db.query(
      'RoomParticipants',
      where: 'userId = ?',
      whereArgs: [userId],
    );
    return results.map((map) => map['roomId'] as String).toList();
  }

  /// Remove a participant from a room
  Future<void> removeRoomParticipant(String roomId, String userId) async {
    final db = await _databaseService.database;
    await db.delete(
      'RoomParticipants',
      where: 'roomId = ? AND userId = ?',
      whereArgs: [roomId, userId],
    );
  }

  /// Remove all participants from a room
  Future<void> removeAllParticipants(String roomId) async {
    final db = await _databaseService.database;
    await db.delete(
      'RoomParticipants',
      where: 'roomId = ?',
      whereArgs: [roomId],
    );
  }

  Future<void> leaveRoom(String roomId, String userId) async {
    final db = await _databaseService.database;

    await db.transaction((txn) async {
      // First get the room to check number of members
      final result = await txn.query(
        'Rooms',
        where: 'roomId = ?',
        whereArgs: [roomId],
      );
      final room = result.isNotEmpty ? Room.fromMap(result.first) : null;
      if (room == null) return;

      // Get all users in the room before removing relationships
      final usersInRoom = await txn.query(
        'RoomParticipants',
        where: 'roomId = ?',
        whereArgs: [roomId],
        columns: ['userId'],
      );
      final userIds = usersInRoom.map((u) => u['userId'] as String).toList();

      // Remove user from room participants
      await txn.delete(
        'RoomParticipants',
        where: 'roomId = ? AND userId = ?',
        whereArgs: [roomId, userId],
      );

      // Get remaining participants using transaction
      final remainingParticipants = await txn.query(
        'RoomParticipants',
        where: 'roomId = ?',
        whereArgs: [roomId],
      );

      // If no participants left, delete the room entirely
      if (remainingParticipants.isEmpty) {
        await txn.delete(
          'Rooms',
          where: 'roomId = ?',
          whereArgs: [roomId],
        );

        await txn.delete(
          'UserRelationships',
          where: 'roomId = ?',
          whereArgs: [roomId],
        );
      } else {
        // Update room members list
        final updatedMembers = room.members.where((m) => m != userId).toList();
        await txn.update(
          'Rooms',
          {'members': updatedMembers.join(',')},
          where: 'roomId = ?',
          whereArgs: [roomId],
        );
      }

      // Check each user in the room and delete if they have no other relationships
      for (final affectedUserId in userIds) {
        if (affectedUserId == userId) continue;

        // Check if user is in any other rooms using transaction
        final otherRooms = await txn.rawQuery('''
        SELECT COUNT(*) as count 
        FROM RoomParticipants 
        WHERE userId = ? AND roomId != ?
      ''', [affectedUserId, roomId]);

        final int roomCount = Sqflite.firstIntValue(otherRooms) ?? 0;

        if (roomCount == 0) {
          // Delete from Users table using transaction
          await txn.delete(
            'Users',
            where: 'userId = ?',
            whereArgs: [affectedUserId],
          );

          // Delete relationships using transaction
          await txn.delete(
            'UserRelationships',
            where: 'userId = ?',
            whereArgs: [affectedUserId],
          );

          print('Deleted orphaned user: $affectedUserId');
        }
      }
    });
  }

  /// Delete a Room by its ID
  Future<void> deleteRoom(String roomId) async {
    final db = await _databaseService.database;
    await db.delete(
      'Rooms',
      where: 'roomId = ?',
      whereArgs: [roomId],
    );
  }

  /// Get all direct (1:1) Rooms
  Future<List<Room>> getDirectRooms() async {
    final db = await _databaseService.database;
    final results = await db.query(
      'Rooms',
      where: 'isGroup = 0', // Assuming isGroup = 0 means direct room
    );
    return results.map((map) => Room.fromMap(map)).toList();
  }

  /// Get all group Rooms
  Future<List<Room>> getGroupRooms() async {
    final db = await _databaseService.database;
    final results = await db.query(
      'Rooms',
      where: 'isGroup = 1',
    );
    return results.map((map) => Room.fromMap(map)).toList();
  }

  /// Get the last activity timestamp for a specific room
  Future<String?> getLastActivity(String roomId) async {
    final db = await _databaseService.database;
    final result = await db.query(
      'Rooms',
      columns: ['lastActivity'],
      where: 'roomId = ?', // Use `roomId` instead of `id`
      whereArgs: [roomId],
    );
    if (result.isNotEmpty) {
      return result.first['lastActivity'] as String;
    }
    return null;
  }

  /// Update the last activity timestamp for a specific room
  Future<void> updateLastActivity(String roomId, String timestamp) async {
    final db = await _databaseService.database;
    await db.update(
      'Rooms',
      {'lastActivity': timestamp},
      where: 'roomId = ?', // Use `roomId` instead of `id`
      whereArgs: [roomId],
    );
  }

  /// Get expired group Rooms
  Future<List<Room>> getExpiredRooms() async {
    final db = await _databaseService.database;
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final results = await db.query(
      'Rooms',
      where: 'isGroup = 1 AND expirationTimestamp > 0 AND expirationTimestamp < ?',
      whereArgs: [currentTimestamp],
    );

    return results.map((map) => Room.fromMap(map)).toList();
  }

  /// Get non-expired group Rooms
  Future<List<Room>> getNonExpiredRooms() async {
    final db = await _databaseService.database;
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final results = await db.query(
      'Rooms',
      where: 'isGroup = 1 AND (expirationTimestamp = 0 OR expirationTimestamp > ?)',
      whereArgs: [currentTimestamp],
    );

    return results.map((map) => Room.fromMap(map)).toList();
  }

  /// Get a Room by its ID
  Future<Room?> getRoomById(String roomId) async {
    final db = await _databaseService.database;
    final result = await db.query(
      'Rooms',
      where: 'roomId = ?', // Use `roomId` instead of `id`
      whereArgs: [roomId],
    );
    if (result.isNotEmpty) {
      return Room.fromMap(result.first);
    }
    return null;
  }

  /// Update a Room in the database
  Future<void> updateRoom(Room room) async {
    final db = await _databaseService.database;
    await db.update(
      'Rooms',
      room.toMap(),
      where: 'roomId = ?', // Use `roomId` instead of `id`
      whereArgs: [room.roomId],
    );
  }
}
