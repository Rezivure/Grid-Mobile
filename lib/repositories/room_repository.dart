import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/room.dart';
import 'package:grid_frontend/services/database_service.dart';

class RoomRepository {
  final DatabaseService _databaseService;

  RoomRepository(this._databaseService);

  static Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE Rooms (
        id TEXT PRIMARY KEY,
        name TEXT,
        isDirect INTEGER,
        lastActivity TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE RoomParticipants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        roomId TEXT,
        userId TEXT,
        FOREIGN KEY (roomId) REFERENCES Rooms (id),
        FOREIGN KEY (userId) REFERENCES Users (id)
      );
    ''');
  }

  Future<void> insertRoom(Room room) async {
    final db = await _databaseService.database;
    await db.insert('Rooms', room.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Room>> getAllRooms() async {
    final db = await _databaseService.database;
    final results = await db.query('Rooms');
    return results.map((map) => Room.fromMap(map)).toList();
  }
}
