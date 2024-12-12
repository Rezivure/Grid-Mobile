import 'package:sqflite/sqflite.dart';
import 'package:grid_frontend/services/database_service.dart';

class UserKeysRepository {
  final DatabaseService _databaseService;

  UserKeysRepository(this._databaseService);

  /// Create the UserKeys table
  static Future<void> createTable(Database db) async {
    await db.execute('''
    CREATE TABLE UserKeys (
      userId TEXT PRIMARY KEY,
      curve25519Key TEXT NOT NULL,
      ed25519Key TEXT NOT NULL,
      approvedKeys TEXT DEFAULT 'false'
    );
  ''');
  }


  /// Insert or update user keys
  Future<void> upsertKeys(String userId, String curve25519Key, String ed25519Key) async {
    final db = await _databaseService.database;
    await db.insert(
      'UserKeys',
      {
        'userId': userId,
        'curve25519Key': curve25519Key,
        'ed25519Key': ed25519Key,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get keys for a specific user
  Future<Map<String, String>?> getKeysByUserId(String userId) async {
    final db = await _databaseService.database;
    final results = await db.query(
      'UserKeys',
      where: 'userId = ?',
      whereArgs: [userId],
    );
    if (results.isNotEmpty) {
      return {
        'curve25519Key': results.first['curve25519Key'] as String,
        'ed25519Key': results.first['ed25519Key'] as String,
      };
    }
    return null;
  }

  /// Get all user keys
  Future<List<Map<String, String>>> getAllKeys() async {
    final db = await _databaseService.database;
    final results = await db.query('UserKeys');
    return results.map((row) {
      return {
        'userId': row['userId'] as String,
        'curve25519Key': row['curve25519Key'] as String,
        'ed25519Key': row['ed25519Key'] as String,
      };
    }).toList();
  }

  /// Delete keys for a specific user
  Future<void> deleteKeysByUserId(String userId) async {
    final db = await _databaseService.database;
    await db.delete('UserKeys', where: 'userId = ?', whereArgs: [userId]);
  }

  /// Delete all keys
  Future<void> deleteAllKeys() async {
    final db = await _databaseService.database;
    await db.delete('UserKeys');
  }

  /// Get the approval status of keys for a specific user
  Future<bool?> getApprovedKeys(String userId) async {
    final db = await _databaseService.database;
    final result = await db.query(
      'UserKeys',
      columns: ['approvedKeys'],
      where: 'userId = ?',
      whereArgs: [userId],
    );
    if (result.isNotEmpty) {
      return result.first['approvedKeys']?.toString().toLowerCase() == 'true';
    }
    return null; // Returns null if no record is found for userId
  }

  Future<void> updateApprovedKeys(String userId, bool approvedKeys) async {
    final db = await _databaseService.database;

    // Update all device keys for the given user to the new approval status
    await db.update(
      'UserKeys', // Assuming the table is called 'UserKeys'
      {'approvedKeys': approvedKeys.toString()}, // Set the approval status
      where: 'userId = ?', // Ensure it targets only the specified user's keys
      whereArgs: [userId],
    );
  }


}
