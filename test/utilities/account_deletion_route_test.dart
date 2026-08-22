import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/utilities/account_deletion_route.dart';

void main() {
  const defaultHs = 'https://matrix.mygrid.app';

  group('resolveAccountDeletionRoute', () {
    test('default serverType + phone number => SMS flow', () {
      expect(
        resolveAccountDeletionRoute(
          serverType: 'default',
          homeserver: defaultHs,
          defaultHomeserver: defaultHs,
          phoneNumber: '+15551234567',
        ),
        AccountDeletionRoute.sms,
      );
    });

    test('default serverType + no phone => passkey manual support', () {
      expect(
        resolveAccountDeletionRoute(
          serverType: 'default',
          homeserver: defaultHs,
          defaultHomeserver: defaultHs,
          phoneNumber: null,
        ),
        AccountDeletionRoute.passkeyManualSupport,
      );
    });

    test('default serverType + empty phone => passkey manual support', () {
      expect(
        resolveAccountDeletionRoute(
          serverType: 'default',
          homeserver: defaultHs,
          defaultHomeserver: defaultHs,
          phoneNumber: '',
        ),
        AccountDeletionRoute.passkeyManualSupport,
      );
    });

    test('matching homeserver (serverType null) + no phone => passkey', () {
      // Passkey-only account where serverType wasn't persisted but the
      // homeserver still matches the default: must NOT fall into SMS.
      expect(
        resolveAccountDeletionRoute(
          serverType: null,
          homeserver: defaultHs,
          defaultHomeserver: defaultHs,
          phoneNumber: null,
        ),
        AccountDeletionRoute.passkeyManualSupport,
      );
    });

    test('homeserver match tolerates surrounding whitespace', () {
      expect(
        resolveAccountDeletionRoute(
          serverType: null,
          homeserver: '  $defaultHs  ',
          defaultHomeserver: defaultHs,
          phoneNumber: '+15551234567',
        ),
        AccountDeletionRoute.sms,
      );
    });

    test('custom homeserver => password deactivation flow', () {
      expect(
        resolveAccountDeletionRoute(
          serverType: 'custom',
          homeserver: 'https://matrix.example.org',
          defaultHomeserver: defaultHs,
          phoneNumber: null,
        ),
        AccountDeletionRoute.customServerPassword,
      );
    });

    test('custom server ignores phone presence', () {
      expect(
        resolveAccountDeletionRoute(
          serverType: 'custom',
          homeserver: 'https://matrix.example.org',
          defaultHomeserver: defaultHs,
          phoneNumber: '+15551234567',
        ),
        AccountDeletionRoute.customServerPassword,
      );
    });
  });
}
