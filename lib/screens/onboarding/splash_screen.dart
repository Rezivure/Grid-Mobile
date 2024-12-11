import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  // Load token from SharedPreferences
  Future<String?> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(Duration(seconds: 2));

    // Load the token from SharedPreferences
    String? token = await _loadFromPrefs();
    print(token);

    final client = Provider.of<Client>(context, listen: false);

    if (token != null && token.isNotEmpty) {
      // If token exists, set it to the client and sync
      try {
        client.accessToken = token;
        await client.sync();
        var stat = client.isLogged();
        print("print stat of client log:{$stat} ");
        if (client.isLogged()) {
          Navigator.pushReplacementNamed(context, '/main');
          return;
        }
      } catch (e) {
        print('Token is invalid or session expired: $e');
      }
    }

    // If token is null or invalid, go to welcome screen
    Navigator.pushReplacementNamed(context, '/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Image.asset(
          'assets/logos/png-file-2.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
