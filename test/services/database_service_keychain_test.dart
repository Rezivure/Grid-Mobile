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

    test('rethrows keychain errors so -25308 queueing still works', () async {
      when(() => primary.read(key: 'encryptionKey'))
          .thenThrow(lockedKeychain());
      when(() => legacy.read(key: 'encryptionKey'))
          .thenThrow(lockedKeychain());

      expect(service.getEncryptionKey(), throwsA(isA<PlatformException>()));
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
