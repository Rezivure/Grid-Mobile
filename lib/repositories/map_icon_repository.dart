import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/map_icon.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'dart:convert';

class MapIconRepository {
  final DatabaseService _databaseService;

  MapIconRepository(this._databaseService);

  /// Create the MapIcons table
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MapIcons (
        id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL,
        creator_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        icon_type TEXT NOT NULL,
        icon_data TEXT NOT NULL,
        name TEXT,
        description TEXT,
        created_at TEXT NOT NULL,
        expires_at TEXT,
        metadata TEXT
      )
    ''');
    
    // Create indexes for better query performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_map_icons_room_id ON MapIcons(room_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_map_icons_creator_id ON MapIcons(creator_id)');
  }

  /// Insert a new map icon
  Future<void> insertMapIcon(MapIcon icon) async {
    final db = await _databaseService.database;
    final data = icon.toDatabase();
    
    // Convert metadata to JSON string if it exists
    if (data['metadata'] != null) {
      data['metadata'] = jsonEncode(data['metadata']);
    }
    
    await db.insert(
      'MapIcons',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all map icons for a specific room
  Future<List<MapIcon>> getIconsForRoom(String roomId) async {
    final db = await _databaseService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'MapIcons',
      where: 'room_id = ?',
      whereArgs: [roomId],
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      final map = Map<String, dynamic>.from(maps[i]);
      // Parse metadata JSON string back to Map
      if (map['metadata'] != null && map['metadata'] is String) {
        map['metadata'] = jsonDecode(map['metadata']);
      }
      return MapIcon.fromDatabase(map);
    });
  }

  /// Get all map icons for multiple rooms (useful for groups view)
  Future<List<MapIcon>> getIconsForRooms(List<String> roomIds) async {
    if (roomIds.isEmpty) return [];
    
    final db = await _databaseService.database;
    final placeholders = List.filled(roomIds.length, '?').join(',');
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT * FROM MapIcons WHERE room_id IN ($placeholders) ORDER BY created_at DESC',
      roomIds,
    );

    return List.generate(maps.length, (i) {
      final map = Map<String, dynamic>.from(maps[i]);
      // Parse metadata JSON string back to Map
      if (map['metadata'] != null && map['metadata'] is String) {
        map['metadata'] = jsonDecode(map['metadata']);
      }
      return MapIcon.fromDatabase(map);
    });
  }

  /// Get all active map icons (not expired)
  Future<List<MapIcon>> getActiveIcons() async {
    final db = await _databaseService.database;
    final now = DateTime.now().toIso8601String();
    
    final List<Map<String, dynamic>> maps = await db.query(
      'MapIcons',
      where: 'expires_at IS NULL OR expires_at > ?',
      whereArgs: [now],
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      final map = Map<String, dynamic>.from(maps[i]);
      // Parse metadata JSON string back to Map
      if (map['metadata'] != null && map['metadata'] is String) {
        map['metadata'] = jsonDecode(map['metadata']);
      }
      return MapIcon.fromDatabase(map);
    });
  }

  /// Get icons created by a specific user
  Future<List<MapIcon>> getIconsByCreator(String creatorId) async {
    final db = await _databaseService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'MapIcons',
      where: 'creator_id = ?',
      whereArgs: [creatorId],
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      final map = Map<String, dynamic>.from(maps[i]);
      // Parse metadata JSON string back to Map
      if (map['metadata'] != null && map['metadata'] is String) {
        map['metadata'] = jsonDecode(map['metadata']);
      }
      return MapIcon.fromDatabase(map);
    });
  }

  /// Delete a specific map icon
  Future<void> deleteMapIcon(String id) async {
    final db = await _databaseService.database;
    await db.delete(
      'MapIcons',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete all icons for a room
  Future<void> deleteIconsForRoom(String roomId) async {
    final db = await _databaseService.database;
    await db.delete(
      'MapIcons',
      where: 'room_id = ?',
      whereArgs: [roomId],
    );
  }

  /// Delete expired icons
  Future<void> deleteExpiredIcons() async {
    final db = await _databaseService.database;
    final now = DateTime.now().toIso8601String();
    
    await db.delete(
      'MapIcons',
      where: 'expires_at IS NOT NULL AND expires_at <= ?',
      whereArgs: [now],
    );
  }

  /// Update a map icon
  Future<void> updateMapIcon(MapIcon icon) async {
    final db = await _databaseService.database;
    final data = icon.toDatabase();
    
    // Convert metadata to JSON string if it exists
    if (data['metadata'] != null) {
      data['metadata'] = jsonEncode(data['metadata']);
    }
    
    await db.update(
      'MapIcons',
      data,
      where: 'id = ?',
      whereArgs: [icon.id],
    );
  }
}