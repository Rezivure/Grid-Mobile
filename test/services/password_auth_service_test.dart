import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grid_frontend/services/password_auth_service.dart';

/// The status-code-to-exception mapping is the whole point of this service.
/// If a 401 escapes as a bare `Exception`, `showErrorReportDialog` fires and a
/// user who simply mistyped their password is told to go post in Discord.
void main() {
  const baseUrl = 'https://gauth.example.test';

  PasswordAuthService serviceReturning(
    http.Response Function(http.Request request) handler, {
    List<http.Request>? captured,
  }) {
    return PasswordAuthService(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        captured?.add(request);
        return handler(request);
      }),
    );
  }

  http.Response json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  group('signup', () {
    test('returns the jwt on 200', () async {
      final service = serviceReturning(
        (_) => json(200, {'jwt': 'tok.en.value', 'username': 'anyabeech'}),
      );

      final jwt = await service.signup(
        username: 'anyabeech',
        password: 'correct horse battery',
        turnstileToken: 'ts',
      );

      expect(jwt, 'tok.en.value');
    });

    test('posts to /auth/password/signup with the expected body', () async {
      final captured = <http.Request>[];
      final service = serviceReturning(
        (_) => json(200, {'jwt': 'x'}),
        captured: captured,
      );

      await service.signup(
        username: 'anyabeech',
        password: 'correct horse battery',
        turnstileToken: 'ts-token',
      );

      expect(captured.single.url.toString(), '$baseUrl/auth/password/signup');
      expect(captured.single.method, 'POST');
      final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
      expect(body['username'], 'anyabeech');
      expect(body['password'], 'correct horse battery');
      expect(body['turnstile_token'], 'ts-token');
    });

    test('sends the password verbatim, without trimming', () async {
      final captured = <http.Request>[];
      final service = serviceReturning(
        (_) => json(200, {'jwt': 'x'}),
        captured: captured,
      );

      await service.signup(
        username: '  anyabeech  ',
        password: '  spaces matter  ',
        turnstileToken: 'ts',
      );

      final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
      // The username is trimmed (it is canonicalised server-side anyway)...
      expect(body['username'], 'anyabeech');
      // ...the password never is. Trimming here would create an account the
      // user can never sign back in to, with no reset available.
      expect(body['password'], '  spaces matter  ');
    });

    test('maps a 400 turnstile failure to TurnstileFailedException', () {
      final service = serviceReturning(
        (_) => json(400, {'detail': 'Verification failed. Please try again.'}),
      );

      expect(
        () => service.signup(
          username: 'anyabeech',
          password: 'correct horse battery',
          turnstileToken: 'stale',
        ),
        throwsA(isA<TurnstileFailedException>()),
      );
    });

    test('maps a 400 policy failure to WeakPasswordException and echoes it', () {
      final service = serviceReturning(
        (_) => json(400, {'detail': 'Password must be at least 10 characters.'}),
      );

      expect(
        () => service.signup(
          username: 'anyabeech',
          password: 'short',
          turnstileToken: 'ts',
        ),
        throwsA(
          isA<WeakPasswordException>().having(
            (e) => e.message,
            'message',
            'Password must be at least 10 characters.',
          ),
        ),
      );
    });

    test('maps a 400 username-taken failure to WeakPasswordException', () {
      // Not strictly a password problem, but it is still a user-fixable 400
      // and must stay inline rather than opening the error-report dialog.
      final service = serviceReturning(
        (_) => json(400, {'detail': 'Username already taken.'}),
      );

      expect(
        () => service.signup(
          username: 'anyabeech',
          password: 'correct horse battery',
          turnstileToken: 'ts',
        ),
        throwsA(isA<WeakPasswordException>()),
      );
    });

    test('throws a plain Exception on a 500 so the report dialog fires', () {
      final service = serviceReturning((_) => http.Response('upstream boom', 500));

      expect(
        () => service.signup(
          username: 'anyabeech',
          password: 'correct horse battery',
          turnstileToken: 'ts',
        ),
        throwsA(
          allOf(
            isA<Exception>(),
            isNot(isA<InvalidCredentialsException>()),
            isNot(isA<TurnstileFailedException>()),
            isNot(isA<WeakPasswordException>()),
          ),
        ),
      );
    });

    test('throws when a 200 carries no jwt', () {
      final service = serviceReturning((_) => json(200, {'username': 'anyabeech'}));

      expect(
        () => service.signup(
          username: 'anyabeech',
          password: 'correct horse battery',
          turnstileToken: 'ts',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('login', () {
    test('returns the jwt on 200', () async {
      final service = serviceReturning((_) => json(200, {'jwt': 'login.jwt'}));

      final jwt = await service.login(
        username: 'anyabeech',
        password: 'correct horse battery',
        turnstileToken: 'ts',
      );

      expect(jwt, 'login.jwt');
    });

    test('posts to /auth/password/login and always sends a turnstile token', () async {
      final captured = <http.Request>[];
      final service = serviceReturning(
        (_) => json(200, {'jwt': 'x'}),
        captured: captured,
      );

      await service.login(
        username: 'anyabeech',
        password: 'correct horse battery',
        turnstileToken: 'ts-token',
      );

      expect(captured.single.url.toString(), '$baseUrl/auth/password/login');
      final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
      expect(body['turnstile_token'], 'ts-token');
    });

    test('maps a 401 to InvalidCredentialsException, NOT a generic Exception', () {
      final service = serviceReturning(
        (_) => json(401, {'detail': 'Incorrect username or password.'}),
      );

      expect(
        () => service.login(
          username: 'anyabeech',
          password: 'wrong password!',
          turnstileToken: 'ts',
        ),
        throwsA(
          isA<InvalidCredentialsException>().having(
            (e) => e.message,
            'message',
            'Incorrect username or password.',
          ),
        ),
      );
    });

    test('repeated wrong passwords keep returning 401 - there is no lockout', () async {
      // Per-account lockout was deliberately removed from the middleware:
      // Grid handles are public, so it would have been a free denial of
      // service against any account whose name you know.
      var calls = 0;
      final service = serviceReturning((_) {
        calls++;
        return json(401, {'detail': 'Incorrect username or password.'});
      });

      for (var i = 0; i < 6; i++) {
        await expectLater(
          service.login(
            username: 'anyabeech',
            password: 'wrong password!',
            turnstileToken: 'ts',
          ),
          throwsA(isA<InvalidCredentialsException>()),
        );
      }
      expect(calls, 6);
    });

    test('maps a spent turnstile token to TurnstileFailedException', () {
      final service = serviceReturning(
        (_) => json(400, {'detail': 'Turnstile verification failed.'}),
      );

      expect(
        () => service.login(
          username: 'anyabeech',
          password: 'correct horse battery',
          turnstileToken: 'already-spent',
        ),
        throwsA(isA<TurnstileFailedException>()),
      );
    });

    test('falls back to a generic message when the body is not JSON', () {
      final service = serviceReturning(
        (_) => http.Response('<html>502 Bad Gateway</html>', 401),
      );

      expect(
        () => service.login(
          username: 'anyabeech',
          password: 'correct horse battery',
          turnstileToken: 'ts',
        ),
        throwsA(
          isA<InvalidCredentialsException>().having(
            (e) => e.message,
            'message',
            'Incorrect username or password.',
          ),
        ),
      );
    });

    test('propagates a socket-level failure untouched', () {
      final service = PasswordAuthService(
        baseUrl: baseUrl,
        client: MockClient((_) async => throw const _NoNetwork()),
      );

      expect(
        () => service.login(
          username: 'anyabeech',
          password: 'correct horse battery',
          turnstileToken: 'ts',
        ),
        throwsA(isA<_NoNetwork>()),
      );
    });
  });

  group('setPassword', () {
    test('sends the bearer token and omits current_password when null', () async {
      final captured = <http.Request>[];
      final service = serviceReturning(
        (_) => json(200, {'status': 'ok'}),
        captured: captured,
      );

      await service.setPassword(jwt: 'my.jwt', newPassword: 'brand new pass');

      expect(captured.single.url.toString(), '$baseUrl/auth/password/set');
      expect(captured.single.headers['Authorization'], 'Bearer my.jwt');
      final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
      expect(body['new_password'], 'brand new pass');
      expect(body.containsKey('current_password'), isFalse);
    });

    test('includes current_password when supplied', () async {
      final captured = <http.Request>[];
      final service = serviceReturning(
        (_) => json(200, {'status': 'ok'}),
        captured: captured,
      );

      await service.setPassword(
        jwt: 'my.jwt',
        newPassword: 'brand new pass',
        currentPassword: 'the old one',
      );

      final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
      expect(body['current_password'], 'the old one');
    });

    test('maps a wrong current password to InvalidCredentialsException', () {
      final service = serviceReturning(
        (_) => json(401, {'detail': 'Incorrect username or password.'}),
      );

      expect(
        () => service.setPassword(
          jwt: 'my.jwt',
          newPassword: 'brand new pass',
          currentPassword: 'not the old one',
        ),
        throwsA(isA<InvalidCredentialsException>()),
      );
    });

    test('maps a policy rejection to WeakPasswordException', () {
      final service = serviceReturning(
        (_) => json(400, {'detail': 'Password cannot be the same as your username.'}),
      );

      expect(
        () => service.setPassword(jwt: 'my.jwt', newPassword: 'anyabeech1'),
        throwsA(isA<WeakPasswordException>()),
      );
    });
  });

  group('status', () {
    test('parses the credential status', () async {
      final captured = <http.Request>[];
      final service = serviceReturning(
        (_) => json(200, {
          'has_password': true,
          'has_passkey': true,
          'passkey_count': 2,
        }),
        captured: captured,
      );

      final status = await service.status('my.jwt');

      expect(captured.single.url.toString(), '$baseUrl/auth/password/status');
      expect(captured.single.method, 'GET');
      expect(captured.single.headers['Authorization'], 'Bearer my.jwt');
      expect(status.hasPassword, isTrue);
      expect(status.hasPasskey, isTrue);
      expect(status.passkeyCount, 2);
    });

    test('defaults missing fields rather than throwing', () async {
      final service = serviceReturning((_) => json(200, <String, dynamic>{}));

      final status = await service.status('my.jwt');

      expect(status.hasPassword, isFalse);
      expect(status.hasPasskey, isFalse);
      expect(status.passkeyCount, 0);
    });

    test('throws on an expired or missing jwt', () {
      final service = serviceReturning((_) => json(401, {'detail': 'Not authenticated'}));

      expect(() => service.status('bad.jwt'), throwsA(isA<Exception>()));
    });
  });
}

class _NoNetwork implements Exception {
  const _NoNetwork();
}
