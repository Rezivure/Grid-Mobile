import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/utilities/utils.dart';

/// These two pure functions are the client half of a contract with the auth
/// middleware's `_password_policy_error`. If they drift apart the user sees a
/// green form and a 400 — or, worse, an account created with a password the
/// client would refuse to let them type again.
void main() {
  group('passwordValidationError', () {
    test('accepts a password at the minimum length', () {
      expect(passwordValidationError('a' * kPasswordMinLength), isNull);
    });

    test('rejects one character below the minimum', () {
      expect(
        passwordValidationError('a' * (kPasswordMinLength - 1)),
        contains('at least $kPasswordMinLength'),
      );
    });

    test('rejects an empty password', () {
      expect(passwordValidationError(''), isNotNull);
    });

    test('accepts a password at the maximum length', () {
      expect(passwordValidationError('a' * kPasswordMaxLength), isNull);
    });

    test('rejects one character above the maximum', () {
      expect(
        passwordValidationError('a' * (kPasswordMaxLength + 1)),
        contains('$kPasswordMaxLength characters or fewer'),
      );
    });

    test('rejects an all-whitespace password', () {
      expect(passwordValidationError('            '), isNotNull);
      expect(passwordValidationError('\t\t\t\t\t\t\t\t\t\t\t'), isNotNull);
    });

    test('rejects a password equal to the username, ignoring case', () {
      expect(
        passwordValidationError('AnyaBeech1', username: 'anyabeech1'),
        contains('same as your username'),
      );
    });

    test('ignores surrounding whitespace on the username when comparing', () {
      expect(
        passwordValidationError('anyabeech1', username: '  anyabeech1  '),
        isNotNull,
      );
    });

    test('allows a password that merely contains the username', () {
      expect(
        passwordValidationError('anyabeech1-and-more', username: 'anyabeech1'),
        isNull,
      );
    });

    test('ignores a null or blank username', () {
      expect(passwordValidationError('correct horse battery'), isNull);
      expect(passwordValidationError('correct horse', username: '   '), isNull);
    });

    // The no-trim rule. Trimming client-side but not server-side (or on signup
    // but not login) creates an unrecoverable account, because there is no
    // password reset.
    group('does not trim', () {
      test('counts leading and trailing spaces toward the length', () {
        // 8 real characters plus a space either side = 10, which passes.
        expect(passwordValidationError(' abcdefgh '), isNull);
      });

      test('a trailing space makes an otherwise-short password long enough', () {
        expect(passwordValidationError('a' * (kPasswordMinLength - 1)), isNotNull);
        expect(passwordValidationError('${'a' * (kPasswordMinLength - 1)} '), isNull);
      });

      test('a padded password is not equal to the bare username', () {
        expect(
          passwordValidationError(' anyabeech1 ', username: 'anyabeech1'),
          isNull,
        );
      });

      test('a length-129 password padded to 130 is still too long', () {
        expect(passwordValidationError(' ${'a' * kPasswordMaxLength} '), isNotNull);
      });
    });
  });

  group('passwordConfirmationError', () {
    test('accepts an exact match', () {
      expect(passwordConfirmationError('hunter22222', 'hunter22222'), isNull);
    });

    test('rejects a mismatch', () {
      expect(
        passwordConfirmationError('hunter22222', 'hunter22223'),
        contains('do not match'),
      );
    });

    test('rejects an empty confirmation', () {
      expect(passwordConfirmationError('hunter22222', ''), isNotNull);
    });

    test('is case sensitive', () {
      expect(passwordConfirmationError('Hunter22222', 'hunter22222'), isNotNull);
    });

    test('does not trim: a padded confirmation is a mismatch', () {
      expect(passwordConfirmationError('hunter22222', 'hunter22222 '), isNotNull);
      expect(passwordConfirmationError(' hunter22222', 'hunter22222'), isNotNull);
    });
  });
}
