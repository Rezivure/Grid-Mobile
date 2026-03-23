import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// High-level passkey service for Grid
class PasskeyService {
  final String _baseUrl;
  final PasskeyAuthenticator _authenticator;

  PasskeyService()
      : _baseUrl = dotenv.env['GAUTH_URL'] ?? 'https://gauth.mygrid.app',
        _authenticator = PasskeyAuthenticator();

  /// Login with passkey. Returns JWT on success.
  Future<String> loginWithPasskey({String? phoneNumber}) async {
    try {
      // Step 1: Get authentication options from our server
      final body = <String, dynamic>{};
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        body['phone_number'] = phoneNumber;
      }

      final optionsResponse = await http.post(
        Uri.parse('$_baseUrl/auth/passkey/login/options'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (optionsResponse.statusCode != 200) {
        throw Exception(
            'Failed to get login options: ${optionsResponse.body}');
      }

      final optionsData = jsonDecode(optionsResponse.body);

      // Step 2: Ask the platform authenticator to sign the challenge
      final request = AuthenticateRequestType.fromJson(
        optionsData as Map<String, dynamic>,
      );
      final credential = await _authenticator.authenticate(request);

      // Step 3: Send the signed credential to our server for verification
      final verifyResponse = await http.post(
        Uri.parse('$_baseUrl/auth/passkey/login/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(credential.toJson()),
      );

      if (verifyResponse.statusCode != 200) {
        throw Exception('Failed to verify login: ${verifyResponse.body}');
      }

      final data = jsonDecode(verifyResponse.body);
      return data['jwt'] as String;
    } catch (e) {
      debugPrint('Passkey login error: $e');
      rethrow;
    }
  }

  /// Sign up with passkey. Returns JWT on success.
  Future<String> signupWithPasskey({
    required String username,
    required String turnstileToken,
  }) async {
    try {
      // Step 1: Get signup/registration options from our server
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

      final optionsData = jsonDecode(optionsResponse.body);

      // Step 2: Ask the platform authenticator to create a new credential
      final request = RegisterRequestType.fromJson(
        optionsData as Map<String, dynamic>,
      );
      final credential = await _authenticator.register(request);

      // Step 3: Send the new credential to our server for verification
      final verifyResponse = await http.post(
        Uri.parse('$_baseUrl/auth/passkey/signup/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(credential.toJson()),
      );

      if (verifyResponse.statusCode != 200) {
        throw Exception(
            'Failed to verify signup: ${verifyResponse.body}');
      }

      final data = jsonDecode(verifyResponse.body);
      return data['jwt'] as String;
    } catch (e) {
      debugPrint('Passkey signup error: $e');
      rethrow;
    }
  }

  /// Register a new passkey for an already-authenticated user.
  Future<void> registerPasskey(String jwt) async {
    try {
      // Step 1: Get registration options from our server
      final optionsResponse = await http.post(
        Uri.parse('$_baseUrl/auth/passkey/register/options'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode({}),
      );

      if (optionsResponse.statusCode != 200) {
        throw Exception(
            'Failed to get registration options: ${optionsResponse.body}');
      }

      final optionsData = jsonDecode(optionsResponse.body);

      // Step 2: Ask the platform authenticator to create a new credential
      final request = RegisterRequestType.fromJson(
        optionsData as Map<String, dynamic>,
      );
      final credential = await _authenticator.register(request);

      // Step 3: Send the new credential to our server for verification
      final verifyResponse = await http.post(
        Uri.parse('$_baseUrl/auth/passkey/register/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode(credential.toJson()),
      );

      if (verifyResponse.statusCode != 200) {
        throw Exception(
            'Failed to verify registration: ${verifyResponse.body}');
      }
    } catch (e) {
      debugPrint('Passkey registration error: $e');
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
