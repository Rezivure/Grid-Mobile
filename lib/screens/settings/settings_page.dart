import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:random_avatar/random_avatar.dart';
import '../../services/sync_manager.dart';
import '/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:grid_frontend/services/location_manager.dart';


class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {

  String? deviceID;
  String? identityKey;
  String _selectedProxy = 'None';
  TextEditingController _customProxyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getDeviceAndIdentityKey();
  }

  Future<void> _getDeviceAndIdentityKey() async {
    final client = Provider.of<Client>(context, listen: false);
    final deviceId = client.deviceID;  // Get device ID
    final identityKey = client.identityKey;  // Get identity key

    setState(() {
      this.deviceID = deviceId ?? 'Device ID not available';
      this.identityKey = identityKey.isNotEmpty ? identityKey : 'Identity Key not available';
    });
  }

  void _showInfoModal(String title, String content) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SelectableText(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAvatar(String username) {
    return CircleAvatar(
      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
      child: RandomAvatar(username, height: 80.0, width: 80.0), // Increased size
      radius: 50,  // Slightly larger radius
    );
  }

  // In SettingsPage, update the _logout method:

  Future<void> _logout() async {
    final client = Provider.of<Client>(context, listen: false);
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final sharedPreferences = await SharedPreferences.getInstance();
    final locationManager = Provider.of<LocationManager>(context, listen: false);
    final syncManager = Provider.of<SyncManager>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign Out'),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        // Stop location tracking first
        locationManager.stopTracking();

        // Clear sync manager state
        await syncManager.clearAllState();
        await syncManager.stopSync();

        // Clear database
        await databaseService.deleteAndReinitialize();

        // Clear shared preferences
        await sharedPreferences.clear();

        try {
          if (client.isLogged()) {
            await client.logout();
            print("Logout successful");
          } else {
            print("Client already logged out");
          }
        } catch (e) {
          print("Error during logout: $e");
        }


        // Navigate to welcome screen
        Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sign out: $e')),
        );
      }
    }
  }

  Future<void> _deactivateSMSAccount() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final locationManager = Provider.of<LocationManager>(context, listen: false);
    final client = Provider.of<Client>(context, listen: false);
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final syncManager = Provider.of<SyncManager>(context, listen: false);

    // Confirm deletion with a simple dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete Account'),
        content: Text('Are you sure you want to delete your account? This will permanently delete your account and remove you from all contacts and groups.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete Account', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    // If user canceled or chose "No," just return
    if (shouldDelete != true) {
      return;
    }

    // Grab the phone number from shared prefs
    final phoneNumber = sharedPreferences.getString('phone_number');
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Phone number not found, is this a beta/test account?')),
      );
      return;
    }

    try {
      // Attempt to request deactivation
      final requestSuccess = await authProvider.requestDeactivateAccount(phoneNumber);
      if (!requestSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to request account deactivation')),
        );
        return;
      }

      // Prompt user for the confirmation code that was just sent
      final codeController = TextEditingController();
      final smsCode = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Confirm Deletion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter the confirmation code sent to your phone'),
              TextField(
                controller: codeController,
                decoration: InputDecoration(labelText: 'SMS Code'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, codeController.text),
              child: Text('Delete Account', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      // If user canceled or code is empty, abort
      if (smsCode == null || smsCode.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Confirmation code was not entered')),
        );
        return;
      }

      // Try confirming account deactivation
      final confirmSuccess = await authProvider.confirmDeactivateAccount(phoneNumber, smsCode);
      if (!confirmSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm account deactivation. Please try again.')),
        );
        return;
      }

      // If successful, stop location tracking, syncing, etc.
      locationManager.stopTracking();
      await syncManager.clearAllState();
      await syncManager.stopSync();

      // Clear your local database
      await databaseService.deleteAndReinitialize();

      // Clear all shared preferences
      await sharedPreferences.clear();

      try {
        if (client.isLogged()) {
          await client.logout();
          print("Logout successful");
        } else {
          print("Client already logged out");
        }
      } catch (e) {
        print("Error during logout: $e");
      }

      // Navigate the user back to the welcome screen
      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);

    } catch (e) {
      print('Error during deactivation request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start account deactivation process')),
      );
    }
  }


  Future<void> _deleteAccount() async {

    // first check which server in use
    final client = Provider.of<Client>(context, listen: false);
    final sharedPreferences = await SharedPreferences.getInstance();
    final serverType = sharedPreferences.getString('serverType');
    final homeserver = await client.homeserver;
    final defaultHomeserver = await dotenv.env['MATRIX_SERVER_URL'];
    if (serverType == 'default' || (homeserver?.toString().trim() == defaultHomeserver?.trim())) {
      _deactivateSMSAccount();
      return;
    }


    // currently uses API directly versus SDK
    // due to issues with SDK

    // Step 1: Confirm deactivation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Account'),
        content: Text('Are you sure you want to delete your account? This will permanently delete your account, remove you from all groups and contacts, and delete your account information. This action is irreversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete Account', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Step 2: Prompt for password
    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Deletion', style: TextStyle(color: Colors.red)),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: InputDecoration(labelText: 'Enter your password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, passwordController.text),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (password == null) return;

    // Step 3: Use `http` to send the deactivation request
    final url = Uri.parse('${client.homeserver}/_matrix/client/v3/account/deactivate');
    final authData = {
      "type": "m.login.password",
      "user": client.userID,
      "password": password,
    };
    final body = jsonEncode({
      "auth": authData,
      "erase": true
    });

    try {
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer ${client.accessToken}",
          "Content-Type": "application/json"
        },
        body: body,
      );

      if (response.statusCode == 200) {
        print("Account successfull deleted.");
        final client = Provider.of<Client>(context, listen: false);
        final databaseService = Provider.of<DatabaseService>(context, listen: false);
        final syncManager = Provider.of<SyncManager>(context, listen: false);

        final locationManager = Provider.of<LocationManager>(context, listen: false);
        locationManager.stopTracking();
        syncManager.stopSync();
        databaseService.deleteAndReinitialize();
        await sharedPreferences.clear();


        try {
          if (client.isLogged()) {
            client.logout();
          } else {
            // do nothing
          }
        } catch (e) {
          print("error logging out post account deletion: $e");
        }

        Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
      } else {
        print("Failed to delete account: ${response.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: ${response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }



  Future<void> _launchURL(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  Widget _buildInfoBubble(String label, String value) {
    return GestureDetector(
      onTap: () => _showInfoModal(label, value),
      child: Container(
        width: double.infinity, // Ensures the bubble takes the full width
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        margin: EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.1), // Lighter background for contrast
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
                overflow: TextOverflow.ellipsis, // Ellipsis if text overflows
              ),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final client = Provider.of<Client>(context, listen: false);
    final userName = client.userID?.localpart ?? 'Unknown User';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: colorScheme.background,
        elevation: 0,
        leading: BackButton(color: colorScheme.onBackground),
      ),
      body: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        color: colorScheme.background,
        child: Column(
          children: [
            _buildAvatar(userName),
            SizedBox(height: 10),
            Text(
              '@$userName',
              style: TextStyle(
                fontSize: 20,
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            _buildInfoBubble('Device ID ', deviceID ?? 'Loading...'),
            _buildInfoBubble('Identity Key ', identityKey ?? 'Loading...'),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(top: 30),
                children: <Widget>[
                  _buildSettingsOption(
                    icon: Icons.info,
                    title: 'About',
                    color: colorScheme.onBackground,
                    onTap: () => _launchURL('https://mygrid.app/about'),
                  ),
                  _buildSettingsOption(
                    icon: Icons.lock,
                    title: 'Privacy',
                    color: colorScheme.onBackground,
                    onTap: () => _launchURL('https://mygrid.app/privacy'),
                  ),
                  _buildSettingsOption(
                    icon: Icons.mail,
                    title: 'Feedback',
                    color: colorScheme.onBackground,
                    onTap: () => _launchURL('https://mygrid.app/feedback'),
                  ),
                  _buildSettingsOption(
                    icon: Icons.report,
                    title: 'Report Abuse',
                    color: colorScheme.onBackground,
                    onTap: () => _launchURL('https://mygrid.app/report'),
                  ),
                  Divider(color: colorScheme.onBackground), // Divider uses theme
                  _buildSettingsOption(
                    icon: Icons.delete,
                    title: 'Clear Cache',
                    color: colorScheme.onBackground,
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Clear Cache'),
                          content: Text('Are you sure you want to clear cache? User locations saved on the device will be cleared.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text('Clear Data', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );

                      if (confirmed ?? false) {
                        await Provider.of<DatabaseService>(context, listen: false).deleteAndReinitialize();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('All data has been cleared.')),
                        );
                      }
                    },
                  ),
                  _buildSettingsOption(
                    icon: Icons.logout,
                    title: 'Sign Out',
                    color: Colors.red,
                    onTap: _logout,
                  ),
                  Center(
                    child: TextButton(
                      onPressed: _deleteAccount,
                      child: Text(
                        'Delete Account',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsOption({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16, color: color),
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
