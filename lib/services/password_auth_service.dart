import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Thrown when the auth server rejects a username/password pair.
///
/// The server deliberately returns one generic message for "no such user" and
/// "wrong password" alike, so this exception carries no detail worth branching
/// on — only that the credentials were wrong.
class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException([this.message = 'Incorrect username or password.']);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when the Cloudflare Turnstile token was missing, malformed, expired
/// or already spent.
///
/// Turnstile tokens are single-use with a short TTL, so the caller MUST remount
/// the `TurnstileWidget` (it has no reset API) before letting the user retry.
class TurnstileFailedException implements Exception {
  const TurnstileFailedException([this.message = 'Verification failed. Please try again.']);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when the server's password policy rejects the chosen password.
/// [message] is the server's own wording and is safe to show verbatim — the
/// client validator should normally have caught this first, so seeing one of
/// these means client and server policy have drifted.
class WeakPasswordException implements Exception {
  const WeakPasswordException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Whether the signed-in account currently holds a password, a passkey, or both.
@immutable
class PasswordAuthStatus {
  const PasswordAuthStatus({
    required this.hasPassword,
    required this.hasPasskey,
    required this.passkeyCount,
  });

  final bool hasPassword;
  final bool hasPasskey;
  final int passkeyCount;

  factory PasswordAuthStatus.fromJson(Map<String, dynamic> json) {
    return PasswordAuthStatus(
      hasPassword: json['has_password'] as bool? ?? false,
      hasPasskey: json['has_passkey'] as bool? ?? false,
      passkeyCount: json['passkey_count'] as int? ?? 0,
    );
  }
}

/// Username + password auth against GAUTH, the second door alongside passkeys.
///
/// Shaped like [PasskeyService]: plain `http`, returns the GAUTH JWT as a
/// `String`, and leaves navigation and storage to the screen. Password login
/// must end in a GAUTH JWT (never a native Matrix `m.login.password`) because
/// that JWT is what becomes SharedPreferences `loginToken`, which subscriptions,
/// passkey management and several other features read.
///
/// Unlike [PasskeyService] it takes an injectable [http.Client] so the
/// status-code-to-exception mapping below can be unit tested — that mapping is
/// load-bearing, because it is what keeps `showErrorReportDialog` (a
/// "something is broken, post this in Discord" flow) from firing on a simple
/// wrong password.
class PasswordAuthService {
  PasswordAuthService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? dotenv.env['GAUTH_URL'] ?? 'https://gauth.mygrid.app';

  final http.Client _client;
  final String _baseUrl;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  /// Create an account with a username and password. Returns a GAUTH JWT.
  ///
  /// [password] is sent exactly as typed — never trimmed. See
  /// `passwordValidationError` in `utilities/utils.dart`.
  Future<String> signup({
    required String username,
    required String password,
    required String turnstileToken,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/auth/password/signup'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'username': username.trim(),
        'password': password,
        'turnstile_token': turnstileToken,
      }),
    );

    _throwIfError(response, action: 'signup');
    return _requireJwt(response);
  }

  /// Sign in with a username and password. Returns a GAUTH JWT.
  ///
  /// Turnstile is required on *every* login, not just the first — it is the
  /// only brute-force control, since there is deliberately no per-account
  /// lockout (Grid handles are public, so lockout would be a free DoS).
  Future<String> login({
    required String username,
    required String password,
    required String turnstileToken,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/auth/password/login'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'username': username.trim(),
        'password': password,
        'turnstile_token': turnstileToken,
      }),
    );

    _throwIfError(response, action: 'login');
    return _requireJwt(response);
  }

  /// Set or change the password for the already-authenticated account.
  ///
  /// [currentPassword] is required only when the account already has a
  /// password. A passkey-only user omits it: the JWT, obtained via passkey, is
  /// the proof of ownership.
  Future<void> setPassword({
    required String jwt,
    required String newPassword,
    String? currentPassword,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/auth/password/set'),
      headers: {..._jsonHeaders, 'Authorization': 'Bearer $jwt'},
      body: jsonEncode({
        'new_password': newPassword,
        if (currentPassword != null) 'current_password': currentPassword,
      }),
    );

    _throwIfError(response, action: 'set password');
  }

  /// Which credentials the signed-in account holds, so Settings can render
  /// "Set a password" versus "Change password".
  Future<PasswordAuthStatus> status(String jwt) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/auth/password/status'),
      headers: {..._jsonHeaders, 'Authorization': 'Bearer $jwt'},
    );

    _throwIfError(response, action: 'password status');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return PasswordAuthStatus.fromJson(data);
  }

  /// Maps a non-2xx response onto a typed exception.
  ///
  /// 401 and 400 are *expected* outcomes of a user typing the wrong thing and
  /// get typed exceptions the UI renders inline. Anything else is a genuine
  /// fault and is thrown as a plain [Exception] so the caller escalates it to
  /// the error-report dialog.
  void _throwIfError(http.Response response, {required String action}) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    final detail = _detail(response);

    if (response.statusCode == 401) {
      throw InvalidCredentialsException(
        detail ?? 'Incorrect username or password.',
      );
    }

    if (response.statusCode == 400) {
      // The server returns 400 for both a failed Turnstile check and a failed
      // password policy check, distinguished only by the message. Turnstile is
      // the one that needs a widget remount, so it must be told apart.
      if (_looksLikeTurnstileFailure(detail)) {
        throw TurnstileFailedException(detail ?? 'Verification failed. Please try again.');
      }
      throw WeakPasswordException(detail ?? 'That password is not allowed.');
    }

    throw Exception(
      'Password $action failed (${response.statusCode}): ${detail ?? response.body}',
    );
  }

  static bool _looksLikeTurnstileFailure(String? detail) {
    if (detail == null) return false;
    final d = detail.toLowerCase();
    return d.contains('turnstile') || d.contains('verification');
  }

  /// Pulls FastAPI's `{"detail": "..."}` out of an error body. Tolerates a
  /// non-JSON body (a proxy's HTML error page, say) by returning null rather
  /// than throwing a `FormatException` on top of the real failure.
  static String? _detail(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) return detail.trim();
      }
    } catch (_) {
      // Fall through: an unparseable body is not itself the error to report.
    }
    return null;
  }

  static String _requireJwt(http.Response response) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final jwt = data['jwt'];
    if (jwt is! String || jwt.isEmpty) {
      throw Exception('Auth server returned no token.');
    }
    return jwt;
  }
}
