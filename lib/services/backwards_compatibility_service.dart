// lib/services/backwards_compatibility_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/models/sharing_preferences.dart';

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
}
