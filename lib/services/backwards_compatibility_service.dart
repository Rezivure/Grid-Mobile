// lib/services/backwards_compatibility_service.dart

import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path/path.dart' as path;
import 'package:matrix/matrix.dart';

class BackwardsCompatibilityService {
  final UserRepository _userRepository;
  final SharingPreferencesRepository _sharingPrefsRepo;

  BackwardsCompatibilityService(
      this._userRepository,
      this._sharingPrefsRepo,
      );

  /// Run any "backfill" or "fixup" routines that only need to happen once
  Future<void> runBackfillIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyDone = prefs.getBool('hasBackfillSharingPrefs') ?? false;

    if (alreadyDone) {
      // Already ran once—no need to do it again.
      return;
    }

    // 1. Fetch all direct contacts
    final allDirectContacts = await _userRepository.getDirectContacts();

    // 2. For each contact, check if there's a SharingPreferences row
    for (final contact in allDirectContacts) {
      final contactId = contact.userId;
      final existingPrefs =
      await _sharingPrefsRepo.getSharingPreferences(contactId, 'user');

      if (existingPrefs == null) {
        // 3. Insert a default row
        final defaultPrefs = SharingPreferences(
          targetId: contactId,
          targetType: 'user',
          activeSharing: true,
          shareWindows: [],
        );
        await _sharingPrefsRepo.setSharingPreferences(defaultPrefs);
        print("Created default sharing prefs for $contactId");
      }
    }

    await prefs.setBool('hasBackfillSharingPrefs', true);
    print("Backfill of sharing preferences complete.");
  }

  /// Check if user needs to re-login due to database migration
  static Future<bool> needsReloginForMigration() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if we've already handled the migration
    final hasCompletedVodozemacMigration = prefs.getBool('hasCompletedVodozemacMigration') ?? false;
    if (hasCompletedVodozemacMigration) {
      return false;
    }

    // Check for old Hive database
    final dir = await getApplicationSupportDirectory();
    final oldHivePath = path.join(dir.path, 'grid_app');
    final hiveDirExists = await Directory(oldHivePath).exists();

    // Check if there's an existing token (which would be from olm)
    final hasOldToken = prefs.getString('token') != null;

    // Need migration if:
    // 1. Old Hive database exists OR
    // 2. Has a token but hasn't completed vodozemac migration (meaning it's an old olm token)
    if (hiveDirExists || hasOldToken) {
      print('[Matrix Migration] Migration needed - Hive exists: $hiveDirExists, Has old token: $hasOldToken');
      return true;
    }

    return false;
  }

  /// Mark migration as completed
  static Future<void> markMigrationComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasCleanedOldHiveDB', true);
    await prefs.setBool('hasCompletedVodozemacMigration', true);

    final dir = await getApplicationSupportDirectory();
    final oldHivePath = path.join(dir.path, 'grid_app');
    try {
      await Directory(oldHivePath).delete(recursive: true);
      print('[Matrix Migration] Cleaned up old Hive database');
    } catch (e) {
      print('[Matrix Migration] Failed to clean old Hive database: $e');
    }
  }

  /// Handle Matrix database migration from Hive to SQLite
  static Future<DatabaseApi> createMatrixDatabase() async {
    final dir = await getApplicationSupportDirectory();

    // Check if old Hive database exists
    final oldHivePath = path.join(dir.path, 'grid_app');
    final hiveDirExists = await Directory(oldHivePath).exists();

    // New SQLite database path - using different name to avoid conflicts
    final dbPath = path.join(dir.path, 'grid_app_matrix.db');

    // If migrating from old version, log it
    if (hiveDirExists) {
      print('[Matrix Migration] Found old Hive database at $oldHivePath');
      print('[Matrix Migration] Creating new SQLite database at $dbPath');

      // Check if we should clean up old data
      final prefs = await SharedPreferences.getInstance();
      final hasCleanedHive = prefs.getBool('hasCleanedOldHiveDB') ?? false;

      if (!hasCleanedHive) {
        print('[Matrix Migration] Note: Old Hive database still exists. Users will need to re-login.');
        // Uncomment to auto-clean after successful migration:
        // try {
        //   await Directory(oldHivePath).delete(recursive: true);
        //   await prefs.setBool('hasCleanedOldHiveDB', true);
        //   print('[Matrix Migration] Cleaned up old Hive database');
        // } catch (e) {
        //   print('[Matrix Migration] Failed to clean old Hive database: $e');
        // }
      }
    }

    final sqfliteDb = await sqflite.openDatabase(
      dbPath,
      version: 1,
    );

    final matrixDb = await MatrixSdkDatabase.init(
      'grid_app',
      database: sqfliteDb,
      sqfliteFactory: sqflite.databaseFactory,
    );

    return matrixDb;
  }
}
