import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:passkeys/passkey_auth.dart';
import 'package:passkeys/relying_party_server/relying_party_server.dart';
import 'package:passkeys/relying_party_server/types/types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Custom relying party server that talks to our gauth middleware
class GridRelyingPartyServer implements RelyingPartyServerInterface {
  final String _baseUrl;
  String? _jwt;

  GridRelyingPartyServer()
      : _baseUrl = dotenv.env['GAUTH_URL'] ?? 'https://gauth.mygrid.app';

  void setJwt(String jwt) {
    _jwt = jwt;
  }

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_jwt != null) 'Authorization': 'Bearer $_jwt',
      };

  @override
  Future<RegistrationInitResponse> initRegister(String email) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/passkey/register/options'),
      headers: _authHeaders,
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get registration options: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return RegistrationInitResponse.fromJson(data);
  }

  @override
  Future<String> completeRegister(
      RegistrationCompleteRequest request) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/passkey/register/verify'),
      headers: _authHeaders,
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to verify registration: ${response.body}');
    }

    return response.body;
  }

  @override
  Future<AuthenticationInitResponse> initAuthenticate(String email) async {
    final body = <String, dynamic>{};
    if (email.isNotEmpty) {
      body['phone_number'] = email; // The server uses phone_number field
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/auth/passkey/login/options'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get login options: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return AuthenticationInitResponse.fromJson(data);
  }

  @override
  Future<String> completeAuthenticate(
      AuthenticationCompleteRequest request) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/passkey/login/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to verify login: ${response.body}');
    }

    return response.body;
  }
}

/// High-level passkey service for Grid
class PasskeyService {
  final String _baseUrl;
  late final PasskeyAuth<GridRelyingPartyServer> _passkeyAuth;
  late final GridRelyingPartyServer _relyingParty;

  PasskeyService()
      : _baseUrl = dotenv.env['GAUTH_URL'] ?? 'https://gauth.mygrid.app' {
    _relyingParty = GridRelyingPartyServer();
    _passkeyAuth = PasskeyAuth<GridRelyingPartyServer>(_relyingParty);
  }

  /// Login with passkey. Returns JWT on success.
  Future<String> loginWithPasskey({String? phoneNumber}) async {
    try {
      final result =
          await _passkeyAuth.authenticate(phoneNumber ?? '');
      final data = jsonDecode(result);
      return data['jwt'] as String;
    } catch (e) {
      print('Passkey login error: $e');
      rethrow;
    }
  }

  /// Sign up with passkey. Returns JWT on success.
  Future<String> signupWithPasskey({
    required String username,
    required String turnstileToken,
  }) async {
    try {
      // First get signup options from our custom endpoint
      final optionsResponse = await http.post(
        Uri.parse('$_baseUrl/auth/passkey/signup/options'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'turnstile_token': turnstileToken,
        }),
      );

      if (optionsResponse.statusCode != 200) {
        throw Exception(
            'Failed to get signup options: ${optionsResponse.body}');
      }

      // Use the passkey auth to create credential
      final result = await _passkeyAuth.register(username);

      // The register flow goes through our relying party server which will
      // call signup/verify. Parse the JWT from the result.
      final data = jsonDecode(result);
      return data['jwt'] as String;
    } catch (e) {
      print('Passkey signup error: $e');
      rethrow;
    }
  }

  /// Register a new passkey for an already-authenticated user.
  Future<void> registerPasskey(String jwt) async {
    _relyingParty.setJwt(jwt);
    try {
      await _passkeyAuth.register('');
    } catch (e) {
      print('Passkey registration error: $e');
      rethrow;
    }
  }

  /// List registered passkeys for the current user.
  Future<List<PasskeyInfo>> listPasskeys(String jwt) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/auth/passkey/list'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to list passkeys: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final List<dynamic> passkeys = data['passkeys'] ?? [];
    return passkeys.map((p) => PasskeyInfo.fromJson(p)).toList();
  }

  /// Delete a passkey by credential ID.
  Future<void> deletePasskey(String jwt, String credentialId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/auth/passkey/${Uri.encodeComponent(credentialId)}'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete passkey: ${response.body}');
    }
  }

  /// Check if passkey prompt has been shown already
  static Future<bool> hasShownPasskeyPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('passkey_prompt_shown') ?? false;
  }

  /// Mark passkey prompt as shown
  static Future<void> markPasskeyPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('passkey_prompt_shown', true);
  }
}

class PasskeyInfo {
  final String credentialId;
  final String? name;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  PasskeyInfo({
    required this.credentialId,
    this.name,
    this.createdAt,
    this.lastUsedAt,
  });

  factory PasskeyInfo.fromJson(Map<String, dynamic> json) {
    return PasskeyInfo(
      credentialId: json['credential_id'] as String,
      name: json['name'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.tryParse(json['last_used_at'])
          : null,
    );
  }
}
