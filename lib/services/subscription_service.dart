import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SubscriptionService {
  static const String _mapTokenKey = 'satellite_map_token';
  static const String _mapTokenExpiryKey = 'satellite_map_token_expiry';
  final _secureStorage = FlutterSecureStorage();

  Future<bool> hasActiveSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwt = prefs.getString('loginToken');
      
      if (jwt == null) return false;

      final authUrl = dotenv.env['GAUTH_URL'];
      final response = await http.get(
        Uri.parse('$authUrl/api/subscription/status'),
        headers: {
          'Authorization': 'Bearer $jwt',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['has_subscription'] == true && data['is_active'] == true;
      }
      return false;
    } catch (e) {
      print('Error checking subscription status: $e');
      return false;
    }
  }

  Future<String?> getMapToken() async {
    try {
      // Check if we have a cached token that's still valid
      final cachedToken = await _secureStorage.read(key: _mapTokenKey);
      final expiryStr = await _secureStorage.read(key: _mapTokenExpiryKey);
      
      if (cachedToken != null && expiryStr != null) {
        final expiry = DateTime.parse(expiryStr);
        // Check if token expires in more than 5 minutes
        if (expiry.isAfter(DateTime.now().add(Duration(minutes: 5)))) {
          print('Using cached token, expires at: $expiry');
          return cachedToken;
        } else {
          print('Token expired or expiring soon, getting new one. Expiry was: $expiry');
        }
      }

      // Generate new token
      final prefs = await SharedPreferences.getInstance();
      final jwt = prefs.getString('loginToken');
      
      if (jwt == null) return null;

      final authUrl = dotenv.env['GAUTH_URL'];
      final response = await http.post(
        Uri.parse('$authUrl/api/maps/token'),
        headers: {
          'Authorization': 'Bearer $jwt',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Map token response: $data'); // Debug log
        final token = data['token'];
        final expiresIn = data['expires_in'] ?? 86400; // Default 24 hours
        
        // Decode token to check payload
        final parts = token.split('.');
        if (parts.length == 3) {
          try {
            // Add padding if needed for base64 decoding
            String payload = parts[1];
            switch (payload.length % 4) {
              case 1:
                payload += '===';
                break;
              case 2:
                payload += '==';
                break;
              case 3:
                payload += '=';
                break;
            }
            final decodedPayload = json.decode(utf8.decode(base64Url.decode(payload)));
            print('Token payload: $decodedPayload');
          } catch (e) {
            print('Error decoding token payload: $e');
          }
        }
        
        // Cache the token
        await _secureStorage.write(key: _mapTokenKey, value: token);
        final expiry = DateTime.now().add(Duration(seconds: expiresIn));
        await _secureStorage.write(key: _mapTokenExpiryKey, value: expiry.toIso8601String());
        
        return token;
      }
      return null;
    } catch (e) {
      print('Error getting map token: $e');
      return null;
    }
  }

  Future<void> clearMapToken() async {
    print('Clearing cached map token');
    await _secureStorage.delete(key: _mapTokenKey);
    await _secureStorage.delete(key: _mapTokenExpiryKey);
  }
}