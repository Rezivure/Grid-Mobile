import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:grid_frontend/services/database_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/services/push_notification_service.dart';

class AuthProvider with ChangeNotifier {
  bool _isLoggedIn = false;
  String? _token;
  String? _userId;
  final Client client;
  final DatabaseService databaseService;

  bool get isLoggedIn => _isLoggedIn;
  String? get token => _token;
  String? get userId => _userId;

  AuthProvider(this.client, this.databaseService) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    _token = prefs.getString('token');
    _userId = prefs.getString('userId');
    notifyListeners();
  }

  // Adjusted login to use JWT
  Future<void> loginWithJWT(String jwt) async {
    _isLoggedIn = true;

    final prefs = await SharedPreferences.getInstance();
    //await prefs.setBool('isLoggedIn', _isLoggedIn);
    await prefs.setString('loginToken', jwt);

    // Clear any stored custom homeserver since this is default server login
    await prefs.remove('custom_homeserver');

    try {
      await client.init();

      // Check if we can communicate with the Matrix server
      await client.checkHomeserver(Uri.parse(dotenv.env['MATRIX_SERVER_URL']!));

      await client.login(
        'org.matrix.login.jwt',
        token: jwt,
      );

      // Persist the Synapse access token so splash_screen can restore the session.
      // The JWT in 'loginToken' is a one-time token; the long-lived credential
      // is the Synapse access token stored here as 'token'.
      if (client.accessToken != null) {
        await prefs.setString('token', client.accessToken!);
      }

      final homeserver = await client.homeserver;
      print("Logged in to: $homeserver");

      // Register push notifications
      try {
        final pushService = PushNotificationService(client: client);
        await pushService.register();
      } catch (e) {
        print('Error registering push notifications: $e');
      }
    } catch (e) {
      print('Error initializing Matrix client with JWT: $e');
    }

    notifyListeners();
  }

  Future<void> logout() async {
    // Unregister push notifications before clearing credentials
    try {
      final pushService = PushNotificationService(client: client);
      await pushService.unregister();
    } catch (e) {
      print('Error unregistering push notifications: $e');
    }

    _isLoggedIn = false;
    _token = null;
    _userId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', _isLoggedIn);
    await prefs.remove('token');
    await prefs.remove('userId');
    await prefs.remove('custom_homeserver');

    notifyListeners();
  }

  Future<void> authenticateWithJWT(String jwt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('serverType', 'default');
      await loginWithJWT(jwt);
    } catch (e) {
      print('Failed to authenticate with JWT: $e');
    }
  }

  Future<bool> checkUsernameAvailability(String username) async {
    try {
      var response = await http.post(
        Uri.parse('${dotenv.env['GAUTH_URL']!}/username'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          // GAUTH's /username endpoint still requires the field even though
          // SMS registration is gone; the value is ignored for availability
          // checks. Sending a placeholder keeps the contract satisfied.
          'phone_number': '+10000000000',
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error checking username availability: $e');
      return false;
    }
  }

}