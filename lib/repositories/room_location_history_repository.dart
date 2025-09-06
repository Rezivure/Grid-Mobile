import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/location_history.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/utilities/encryption_utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Repository for managing location history scoped to specific rooms
/// Maintains separate location trails for each user in each room they're part of
class RoomLocationHistoryRepository {
  final DatabaseService _databaseService;
  final StreamController<RoomHistoryUpdate> _historyUpdatesController = 
      StreamController<RoomHistoryUpdate>.broadcast();
  
  // Configuration
  static const int maxDaysToStore = 30;
  static const int minSecondsBetweenPoints = 30; // At least 30 seconds between points
  static const double minDistanceMeters = 10.0; // At least 10 meters movement
  static const int maxPointsPerUserPerRoom = 8640; // 30 days * 288 points/day (5 min intervals)

  RoomLocationHistoryRepository(this._databaseService);

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS RoomLocationHistory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        roomId TEXT NOT NULL,
        userId TEXT NOT NULL,
        pointsData TEXT NOT NULL,
        joinedAt TEXT NOT NULL,
        lastUpdated TEXT NOT NULL,
        iv TEXT NOT NULL,
        UNIQUE(roomId, userId) ON CONFLICT REPLACE,
        FOREIGN KEY (roomId) REFERENCES Rooms(roomId) ON DELETE CASCADE,
        FOREIGN KEY (userId) REFERENCES Users(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_room_location_history 
      ON RoomLocationHistory(roomId, userId);
    ''');
    
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_room_location_history_updated 
      ON RoomLocationHistory(roomId, lastUpdated);
    ''');
  }

  Stream<RoomHistoryUpdate> get historyUpdates => _historyUpdatesController.stream;

  /// Add a location point for a user in a specific room
  Future<void> addLocationPoint({
    required String roomId,
    required String userId,
    required double latitude,
    required double longitude,
    DateTime? joinedAt,
  }) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();
    final now = DateTime.now();
    
    // Get or create join timestamp
    final userJoinedAt = joinedAt ?? await _getUserJoinedAt(roomId, userId) ?? now;
    
    // Get existing history for this user in this room
    final existingHistory = await getRoomLocationHistory(roomId, userId);
    List<LocationPoint> points = existingHistory?.points ?? [];
    
    // Check if we should add this point (rate limiting)
    if (points.isNotEmpty) {
      final lastPoint = points.last;
      final timeDiff = now.difference(lastPoint.timestamp).inSeconds;
      
      // Skip if too soon
      if (timeDiff < minSecondsBetweenPoints) {
        return;
      }
      
      // Check distance moved
      final distance = Geolocator.distanceBetween(
        lastPoint.latitude,
        lastPoint.longitude,
        latitude,
        longitude,
      );
      
      // Skip if hasn't moved enough
      if (distance < minDistanceMeters) {
        return;
      }
    }
    
    // Add new point
    points.add(LocationPoint(
      latitude: latitude,
      longitude: longitude,
      timestamp: now,
    ));
    
    // Clean up old points (30-day rolling window)
    final cutoffDate = now.subtract(Duration(days: maxDaysToStore));
    points = points.where((p) => p.timestamp.isAfter(cutoffDate)).toList();
    
    // Limit total points (should rarely hit this with 30-day window)
    if (points.length > maxPointsPerUserPerRoom) {
      points = points.skip(points.length - maxPointsPerUserPerRoom).toList();
    }
    
    // Sort by timestamp (just to be safe)
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    // Serialize and encrypt
    final pointsJson = points.map((p) => {
      'lat': p.latitude,
      'lng': p.longitude,
      'ts': p.timestamp.toIso8601String(),
    }).toList();
    
    // Generate IV for encryption
    final iv = encrypt.IV.fromSecureRandom(16);
    final encryptedData = encryptText(
      jsonEncode(pointsJson),
      encryptionKey,
      iv,
    );
    
    // Save to database
    await db.insert(
      'RoomLocationHistory',
      {
        'roomId': roomId,
        'userId': userId,
        'pointsData': encryptedData,
        'joinedAt': userJoinedAt.toIso8601String(),
        'lastUpdated': now.toIso8601String(),
        'iv': iv.base64,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    // Notify listeners
    _historyUpdatesController.add(RoomHistoryUpdate(roomId, userId));
  }
  
  /// Get location history for a specific user in a specific room
  Future<LocationHistory?> getRoomLocationHistory(String roomId, String userId) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();
    
    final results = await db.query(
      'RoomLocationHistory',
      where: 'roomId = ? AND userId = ?',
      whereArgs: [roomId, userId],
      limit: 1,
    );
    
    if (results.isEmpty) {
      return null;
    }
    
    final row = results.first;
    
    // Decrypt the data
    final decrypted = decryptText(
      row['pointsData'] as String,
      encryptionKey,
      row['iv'] as String,
    );
    
    // Parse points
    final pointsJson = jsonDecode(decrypted) as List;
    final points = pointsJson.map((p) => LocationPoint(
      latitude: p['lat'] as double,
      longitude: p['lng'] as double,
      timestamp: DateTime.parse(p['ts'] as String),
    )).toList();
    
    // Filter points to only include those after user joined
    final joinedAt = DateTime.parse(row['joinedAt'] as String);
    final filteredPoints = points.where((p) => p.timestamp.isAfter(joinedAt) || 
                                                p.timestamp.isAtSameMomentAs(joinedAt)).toList();
    
    return LocationHistory(
      userId: userId,
      points: filteredPoints,
      lastUpdated: DateTime.parse(row['lastUpdated'] as String),
    );
  }
  
  /// Get all location histories for a room (for group history viewing)
  Future<Map<String, LocationHistory>> getAllRoomHistories(String roomId, {List<String>? userIds}) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();
    
    // Build query
    String whereClause = 'roomId = ?';
    List<dynamic> whereArgs = [roomId];
    
    if (userIds != null && userIds.isNotEmpty) {
      final placeholders = List.filled(userIds.length, '?').join(',');
      whereClause += ' AND userId IN ($placeholders)';
      whereArgs.addAll(userIds);
    }
    
    final results = await db.query(
      'RoomLocationHistory',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'lastUpdated DESC',
    );
    
    final histories = <String, LocationHistory>{};
    
    for (final row in results) {
      final userId = row['userId'] as String;
      
      // Decrypt the data
      final decrypted = decryptText(
        row['pointsData'] as String,
        encryptionKey,
        row['iv'] as String,
      );
      
      // Parse points
      final pointsJson = jsonDecode(decrypted) as List;
      final points = pointsJson.map((p) => LocationPoint(
        latitude: p['lat'] as double,
        longitude: p['lng'] as double,
        timestamp: DateTime.parse(p['ts'] as String),
      )).toList();
      
      // Filter points to only include those after user joined
      final joinedAt = DateTime.parse(row['joinedAt'] as String);
      final filteredPoints = points.where((p) => p.timestamp.isAfter(joinedAt) || 
                                                  p.timestamp.isAtSameMomentAs(joinedAt)).toList();
      
      histories[userId] = LocationHistory(
        userId: userId,
        points: filteredPoints,
        lastUpdated: DateTime.parse(row['lastUpdated'] as String),
      );
    }
    
    return histories;
  }
  
  /// Set when a user joined a room (for filtering history)
  Future<void> setUserJoinedAt(String roomId, String userId, DateTime joinedAt) async {
    final db = await _databaseService.database;
    
    // Check if record exists
    final existing = await db.query(
      'RoomLocationHistory',
      where: 'roomId = ? AND userId = ?',
      whereArgs: [roomId, userId],
      limit: 1,
    );
    
    if (existing.isNotEmpty) {
      // Update joinedAt if record exists
      await db.update(
        'RoomLocationHistory',
        {'joinedAt': joinedAt.toIso8601String()},
        where: 'roomId = ? AND userId = ?',
        whereArgs: [roomId, userId],
      );
    }
    // If no record exists yet, it will be created with correct joinedAt on first location update
  }
  
  /// Get when a user joined a room
  Future<DateTime?> _getUserJoinedAt(String roomId, String userId) async {
    final db = await _databaseService.database;
    
    final results = await db.query(
      'RoomLocationHistory',
      columns: ['joinedAt'],
      where: 'roomId = ? AND userId = ?',
      whereArgs: [roomId, userId],
      limit: 1,
    );
    
    if (results.isEmpty) {
      return null;
    }
    
    return DateTime.parse(results.first['joinedAt'] as String);
  }
  
  /// Clean up old data across all rooms (maintenance task)
  Future<int> cleanupOldData() async {
    final db = await _databaseService.database;
    final cutoffDate = DateTime.now().subtract(Duration(days: maxDaysToStore));
    
    // This is more complex - we need to update each record's points
    // For now, we rely on the per-insert cleanup
    // Could implement a batch job if needed
    
    return 0;
  }
  
  /// Delete all history for a specific room
  Future<void> deleteRoomHistory(String roomId) async {
    final db = await _databaseService.database;
    await db.delete(
      'RoomLocationHistory',
      where: 'roomId = ?',
      whereArgs: [roomId],
    );
  }
  
  /// Delete history for a specific user in a specific room
  Future<void> deleteUserRoomHistory(String roomId, String userId) async {
    final db = await _databaseService.database;
    await db.delete(
      'RoomLocationHistory',
      where: 'roomId = ? AND userId = ?',
      whereArgs: [roomId, userId],
    );
  }
  
  void dispose() {
    _historyUpdatesController.close();
  }
}

/// Event for room history updates
class RoomHistoryUpdate {
  final String roomId;
  final String userId;
  
  RoomHistoryUpdate(this.roomId, this.userId);
}