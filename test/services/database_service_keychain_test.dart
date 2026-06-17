import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:mocktail/mocktail.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockSecureStorage primary;
  late MockSecureStorage legacy;
  late DatabaseService service;

  setUp(() {
    primary = MockSecureStorage();
    legacy = MockSecureStorage();
    service = DatabaseService(secureStorage: primary, legacyStorage: legacy);
  });

  PlatformException lockedKeychain() => PlatformException(
        code: '-25308',
        message: 'User interaction is not allowed.',
      );

  group('hasEncryptionKey', () {
    test('true when primary store has the key', () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenAnswer((_) async => 'the-key');

      expect(await service.hasEncryptionKey(), isTrue);
      verifyNever(() => legacy.read(key: any(named: 'key')));
    });

    test('true + migrates when only legacy store has the key', () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenAnswer((_) async => null);
      when(() => legacy.read(key: 'encryptionKey'))
          .thenAnswer((_) async => 'legacy-key');
      when(() => primary.write(
          key: 'encryptionKey',
          value: 'legacy-key')).thenAnswer((_) async {});
      when(() => legacy.delete(key: 'encryptionKey'))
          .thenAnswer((_) async {});

      expect(await service.hasEncryptionKey(), isTrue);
      verify(() => primary.write(key: 'encryptionKey', value: 'legacy-key'))
          .called(1);
    });

    test('false only when both stores cleanly report no key', () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenAnswer((_) async => null);
      when(() => legacy.read(key: 'encryptionKey'))
          .thenAnswer((_) async => null);

      expect(await service.hasEncryptionKey(), isFalse);
    });

    test('throws (not false) when primary read fails and legacy is empty',
        () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenThrow(lockedKeychain());
      when(() => legacy.read(key: 'encryptionKey'))
          .thenAnswer((_) async => null);

      // A locked keychain must never be reported as "key missing" — that
      // routes into the destructive recovery flow.
      expect(service.hasEncryptionKey(), throwsA(isA<PlatformException>()));
    });

    test('throws when both reads fail', () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenThrow(lockedKeychain());
      when(() => legacy.read(key: 'encryptionKey'))
          .thenThrow(lockedKeychain());

      expect(service.hasEncryptionKey(), throwsA(isA<PlatformException>()));
    });

    test('still finds legacy key when primary read fails', () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenThrow(lockedKeychain());
      when(() => legacy.read(key: 'encryptionKey'))
          .thenAnswer((_) async => 'legacy-key');
      when(() => primary.write(
          key: 'encryptionKey',
          value: 'legacy-key')).thenThrow(lockedKeychain());

      // Migration write failure is non-fatal; the key was found.
      expect(await service.hasEncryptionKey(), isTrue);
    });
  });

  group('isKeychainLocked', () {
    test('matches code == -25308', () {
      expect(
        DatabaseService.isKeychainLocked(
            PlatformException(code: '-25308', message: 'whatever')),
        isTrue,
      );
    });

    test('matches -25308 hidden in message/details', () {
      expect(
        DatabaseService.isKeychainLocked(PlatformException(
          code: 'Unexpected security result code',
          message: 'Code: -25308',
        )),
        isTrue,
      );
      expect(
        DatabaseService.isKeychainLocked(PlatformException(
          code: 'Unexpected security result code',
          message: 'OSStatus',
          details: 'value: -25308',
        )),
        isTrue,
      );
    });

    test('matches "interaction is not allowed" text', () {
      expect(
        DatabaseService.isKeychainLocked(PlatformException(
          code: 'Unexpected security result code',
          message: 'User interaction is not allowed.',
        )),
        isTrue,
      );
    });

    test('does not match unrelated errors', () {
      expect(
        DatabaseService.isKeychainLocked(
            PlatformException(code: '-25300', message: 'item not found')),
        isFalse,
      );
      expect(DatabaseService.isKeychainLocked(Exception('boom')), isFalse);
    });
  });

  group('migration completion', () {
    test('-25299 on migration write still deletes the legacy item', () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenAnswer((_) async => null);
      when(() => legacy.read(key: 'encryptionKey'))
          .thenAnswer((_) async => 'legacy-key');
      // "already exists" — key is already under the new accessibility.
      when(() => primary.write(key: 'encryptionKey', value: 'legacy-key'))
          .thenThrow(PlatformException(
        code: 'Unexpected security result code',
        message: 'The specified item already exists. -25299',
      ));
      when(() => legacy.delete(key: 'encryptionKey'))
          .thenAnswer((_) async {});

      expect(await service.hasEncryptionKey(), isTrue);
      // Legacy item MUST be deleted so it stops throwing -25308 when locked.
      verify(() => legacy.delete(key: 'encryptionKey')).called(1);
    });
  });

  group('getEncryptionKey', () {
    test('throws EncryptionKeyMissingException on clean absence', () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenAnswer((_) async => null);
      when(() => legacy.read(key: 'encryptionKey'))
          .thenAnswer((_) async => null);

      expect(
        service.getEncryptionKey(),
        throwsA(isA<EncryptionKeyMissingException>()),
      );
    });

    test('throws retryable KeychainTemporarilyUnavailableException when locked',
        () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenThrow(lockedKeychain());
      when(() => legacy.read(key: 'encryptionKey'))
          .thenThrow(lockedKeychain());

      // A locked keychain is retryable, NOT "key missing" — callers must be
      // able to distinguish it so they don't wipe / drop data.
      expect(
        service.getEncryptionKey(),
        throwsA(isA<KeychainTemporarilyUnavailableException>()),
      );
    });

    test('caches the key after first successful read', () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenAnswer((_) async => 'the-key');

      expect(await service.getEncryptionKey(), 'the-key');
      expect(await service.getEncryptionKey(), 'the-key');
      verify(() => primary.read(key: 'encryptionKey')).called(1);
    });
  });
}
