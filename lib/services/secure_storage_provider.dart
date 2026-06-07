import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Centralized FlutterSecureStorage factory. iOS uses
// first_unlock_this_device so background launches on a locked phone don't
// throw -25308 ("User interaction is not allowed") and cascade into stuck
// offline state (see Fix A).
//
// Migration is lazy and intentional: items previously written with the
// default WhenUnlocked accessibility stay readable while the device is
// unlocked, and only the next write rewrites them with the new policy.
// No explicit migration code — that would risk losing the encryption key.
class SecureStorageProvider {
  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  // Android: keep defaults — switching to encryptedSharedPreferences would
  // strand existing on-disk values written under the old backend.
  static FlutterSecureStorage instance() => const FlutterSecureStorage(
        iOptions: _iosOptions,
      );
}
