import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:random_avatar/random_avatar.dart';
import '/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/services/location_broadcast_service.dart';
import '/services/location_tracking_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl_phone_field/intl_phone_field.dart';



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

  Future<void> _logout() async {
    final client = Provider.of<Client>(context, listen: false);
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final locationBroadcastService = Provider.of<LocationBroadcastService>(context, listen: false);
    final locationTrackingService = Provider.of<LocationTrackingService>(context, listen: false);
    final sharedPreferences = await SharedPreferences.getInstance();

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
        locationBroadcastService.stopBroadcastingLocation();
        locationTrackingService.stopService();
        await databaseService.clearAllData();
        await sharedPreferences.clear();
        await client.logout();
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
    final client = Provider.of<Client>(context, listen: false);
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final locationBroadcastService = Provider.of<LocationBroadcastService>(context, listen: false);
    final locationTrackingService = Provider.of<LocationTrackingService>(context, listen: false);

    // Step 1: Prompt user to enter their phone number with IntlPhoneField
    String? phoneNumber = await showDialog<String>(
      context: context,
      builder: (context) {
        String formattedPhoneNumber = ''; // Will store the formatted phone number with country code
        return AlertDialog(
          title: Text('Confirm Phone Number'),
          content: IntlPhoneField(
            decoration: InputDecoration(labelText: 'Enter your phone number'),
            initialCountryCode: 'US', // Change this to a default country code
            onChanged: (phone) {
              formattedPhoneNumber = phone.completeNumber; // Capture full phone number with country code
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, formattedPhoneNumber),
              child: Text('Continue'),
            ),
          ],
        );
      },
    );

    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Phone number is required for account deactivation')),
      );
      return;
    }

    // Step 2: Request deactivation via SMS
    final requestSuccess = await authProvider.requestDeactivateAccount(phoneNumber);
    if (!requestSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to request account deactivation')),
      );
      return;
    }

    // Step 3: Prompt user to enter the SMS code
    final codeController = TextEditingController();
    final smsCode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Deactivation'),
        content: TextField(
          controller: codeController,
          decoration: InputDecoration(labelText: 'Enter SMS code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, codeController.text),
            child: Text('Delete (Permanently)', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (smsCode == null || smsCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SMS code is required to confirm deactivation')),
      );
      return;
    }

    // Step 4: Confirm deactivation with the entered code
    final confirmSuccess = await authProvider.confirmDeactivateAccount(phoneNumber, smsCode);
    if (confirmSuccess) {
      print("Account deactivated successfully via SMS.");
      locationBroadcastService.stopBroadcastingLocation();
      locationTrackingService.stopService();
      await databaseService.clearAllData();
      await sharedPreferences.remove('userId'); // double check
      await sharedPreferences.clear();

      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to confirm account deactivation')),
      );
    }
  }


  Future<void> _deactivateAccount() async {

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
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final locationBroadcastService = Provider.of<LocationBroadcastService>(context, listen: false);
    final locationTrackingService = Provider.of<LocationTrackingService>(context, listen: false);

    // Step 1: Confirm deactivation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Deactivate Account'),
        content: Text('Are you sure you want to deactivate your account? This will attempt to erase all locations ever sent, and permanently deactivate your account. This action is irreversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Deactivate Account', style: TextStyle(color: Colors.red)),
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
        title: Text('Confirm Deactivation', style: TextStyle(color: Colors.red)),
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
            child: Text('Deactivate', style: TextStyle(color: Colors.red)),
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
        print("Account deactivated successfully.");
        locationBroadcastService.stopBroadcastingLocation();
        locationTrackingService.stopService();
        await databaseService.clearAllData();
        await sharedPreferences.clear();

        Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
      } else {
        print("Failed to deactivate account: ${response.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to deactivate account: ${response.body}')),
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
                        await Provider.of<DatabaseService>(context, listen: false).clearAllData();
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
                      onPressed: _deactivateAccount,
                      child: Text(
                        'Deactivate Account',
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
