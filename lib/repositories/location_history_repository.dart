import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/models/location_history.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/utilities/encryption_utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class LocationHistoryRepository {
  final DatabaseService _databaseService;
  final StreamController<String> _historyUpdatesController = StreamController<String>.broadcast();

  LocationHistoryRepository(this._databaseService);

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE LocationHistory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT NOT NULL,
        pointsData TEXT NOT NULL,
        lastUpdated TEXT NOT NULL,
        iv TEXT NOT NULL,
        FOREIGN KEY (userId) REFERENCES Users (id) ON DELETE CASCADE,
        UNIQUE(userId) ON CONFLICT REPLACE
      );
    ''');

    await db.execute('''
      CREATE INDEX idx_location_history_user_id ON LocationHistory(userId);
    ''');
  }

  Stream<String> get historyUpdates => _historyUpdatesController.stream;

  Future<void> addLocationPoint(String userId, double latitude, double longitude) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();
    final now = DateTime.now();

    // Get existing history
    LocationHistory? existingHistory = await getLocationHistory(userId);
    List<LocationPoint> points = existingHistory?.points ?? [];

    // Check if we should add this point
    if (points.isNotEmpty) {
      final lastPoint = points.last;
      final timeDiff = now.difference(lastPoint.timestamp).inSeconds;
      
      // Skip if too soon
      if (timeDiff < LocationHistoryConfig.minSecondsBetweenPoints) {
        return;
      }

      // Check distance
      final distance = Geolocator.distanceBetween(
        lastPoint.latitude,
        lastPoint.longitude,
        latitude,
        longitude,
      );

      // Skip if too close
      if (distance < LocationHistoryConfig.minDistanceMeters) {
        return;
      }
    }

    // Add new point
    points.add(LocationPoint(
      latitude: latitude,
      longitude: longitude,
      timestamp: now,
    ));

    // Remove old points (older than 7 days)
    final cutoffDate = now.subtract(Duration(days: LocationHistoryConfig.maxDaysToStore));
    points = points.where((p) => p.timestamp.isAfter(cutoffDate)).toList();

    // Limit total points
    if (points.length > LocationHistoryConfig.maxPointsPerUser) {
      points = points.sublist(points.length - LocationHistoryConfig.maxPointsPerUser);
    }

    // Save updated history
    await _saveLocationHistory(userId, points, now, encryptionKey);
    
    // Notify listeners
    _historyUpdatesController.add(userId);
  }

  Future<void> _saveLocationHistory(
    String userId,
    List<LocationPoint> points,
    DateTime lastUpdated,
    String encryptionKey,
  ) async {
    final db = await _databaseService.database;
    
    // Convert points to JSON
    final pointsJson = jsonEncode(points.map((p) => p.toJson()).toList());
    
    // Generate IV and encrypt the data
    final iv = encrypt.IV.fromSecureRandom(16);
    final encryptedData = encryptText(pointsJson, encryptionKey, iv);
    
    await db.insert(
      'LocationHistory',
      {
        'userId': userId,
        'pointsData': encryptedData,
        'iv': iv.base64,
        'lastUpdated': lastUpdated.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<LocationHistory?> getLocationHistory(String userId) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();
    
    final results = await db.query(
      'LocationHistory',
      where: 'userId = ?',
      whereArgs: [userId],
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

    // Parse JSON
    final pointsList = (jsonDecode(decrypted) as List)
        .map((json) => LocationPoint.fromJson(json))
        .toList();

    return LocationHistory(
      userId: userId,
      points: pointsList,
      lastUpdated: DateTime.parse(row['lastUpdated'] as String),
    );
  }

  Future<Map<String, LocationHistory>> getLocationHistoriesForUsers(List<String> userIds) async {
    final db = await _databaseService.database;
    final encryptionKey = await _databaseService.getEncryptionKey();
    
    if (userIds.isEmpty) return {};

    final placeholders = List.filled(userIds.length, '?').join(',');
    final results = await db.rawQuery(
      'SELECT * FROM LocationHistory WHERE userId IN ($placeholders)',
      userIds,
    );

    final historyMap = <String, LocationHistory>{};

    for (final row in results) {
      final userId = row['userId'] as String;
      
      // Decrypt the data
      final decrypted = decryptText(
        row['pointsData'] as String,
        encryptionKey,
        row['iv'] as String,
      );

      // Parse JSON
      final pointsList = (jsonDecode(decrypted) as List)
          .map((json) => LocationPoint.fromJson(json))
          .toList();

      historyMap[userId] = LocationHistory(
        userId: userId,
        points: pointsList,
        lastUpdated: DateTime.parse(row['lastUpdated'] as String),
      );
    }

    return historyMap;
  }

  Future<void> deleteUserHistory(String userId) async {
    final db = await _databaseService.database;
    await db.delete(
      'LocationHistory',
      where: 'userId = ?',
      whereArgs: [userId],
    );
  }

  Future<void> cleanupOldHistories() async {
    final db = await _databaseService.database;
    final cutoffDate = DateTime.now().subtract(Duration(days: LocationHistoryConfig.maxDaysToStore));
    
    await db.delete(
      'LocationHistory',
      where: 'lastUpdated < ?',
      whereArgs: [cutoffDate.toIso8601String()],
    );
  }
}