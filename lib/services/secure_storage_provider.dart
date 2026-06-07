import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Centralized FlutterSecureStorage factory. iOS uses
// first_unlock_this_device so background launches on a locked phone don't
// throw -25308 ("User interaction is not allowed").
//
// flutter_secure_storage 9.x puts kSecAttrAccessible IN the search query
// (FlutterSecureStorage.swift:35), so items written under the previous
// default (WhenUnlocked) are invisible to a read configured with
// first_unlock_this_device. Use [legacyInstance] to read those and
// DatabaseService migrates on hit.
class SecureStorageProvider {
  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  static FlutterSecureStorage instance() => const FlutterSecureStorage(
        iOptions: _iosOptions,
      );

  // Default accessibility — only used to read items written before the
  // Fix A migration so we can move them under the new accessibility.
  static FlutterSecureStorage legacyInstance() => const FlutterSecureStorage();
}
