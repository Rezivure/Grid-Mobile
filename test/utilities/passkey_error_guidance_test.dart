import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/utilities/passkey_error_guidance.dart';

void main() {
  group('passkeySignupErrorMessage', () {
    final msg = passkeySignupErrorMessage();

    test('does not mention SMS (deprecated, no SMS option exists — GH #285)',
        () {
      expect(msg.toLowerCase(), isNot(contains('sms')));
    });

    test('points to passkey support requirement', () {
      expect(msg.toLowerCase(), contains('passkey'));
    });

    test('offers an actionable next step (retry)', () {
      expect(msg.toLowerCase(), contains('try again'));
    });

    test('offers a real escape hatch (github / team)', () {
      final lower = msg.toLowerCase();
      expect(lower.contains('github') || lower.contains('team'), isTrue);
    });

    test('is non-empty', () {
      expect(msg.trim(), isNotEmpty);
    });
  });

  group('passkeyLoginErrorMessage', () {
    final msg = passkeyLoginErrorMessage();

    test('does not mention SMS (deprecated — GH #285)', () {
      expect(msg.toLowerCase(), isNot(contains('sms')));
    });

    test('mentions same device / password manager guidance', () {
      final lower = msg.toLowerCase();
      expect(lower.contains('device') || lower.contains('password manager'),
          isTrue);
    });

    test('offers an actionable next step (retry)', () {
      expect(msg.toLowerCase(), contains('try again'));
    });

    test('offers a real escape hatch (github / team)', () {
      final lower = msg.toLowerCase();
      expect(lower.contains('github') || lower.contains('team'), isTrue);
    });

    test('is non-empty', () {
      expect(msg.trim(), isNotEmpty);
    });
  });
}
