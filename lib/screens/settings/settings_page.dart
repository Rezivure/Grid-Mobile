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



class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {

  String? deviceID;
  String? identityKey;
  String _selectedProxy = 'None';
  TextEditingController _customProxyController = TextEditingController();
  bool _incognitoMode = false;
  String? _userID;
  String? _username;
  String? _displayName;
  bool _isEditingDisplayName = false;


  @override
  void initState() {
    super.initState();
    _getDeviceAndIdentityKey();
    _loadUser();
    _loadIncognitoState();
  }

  Future<void> _loadUser() async {
    try {
      final client = Provider.of<Client>(context, listen: false);
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userID = client.userID;
        _username = _userID?.split(':')[0].replaceAll('@', '') ?? 'Unknown User';
        _displayName = prefs.getString('displayName') ?? _username;
      });
    } catch (e) {
      print('Error loading user: $e');
      setState(() {
        _username = 'Unknown User';
        _displayName = 'Unknown User';
      });
    }
  }

  Future<void> _loadIncognitoState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _incognitoMode = prefs.getBool('incognito_mode') ?? false;
    });
  }

  Future<void> _toggleIncognitoMode(bool value) async {
    final locationManager = Provider.of<LocationManager>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _incognitoMode = value;
    });

    await prefs.setBool('incognito_mode', value);

    if (value) {
      locationManager.stopTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Your location is no longer being shared.')),
      );
    } else {
      locationManager.startTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Your location is being shared with trusted contacts.')),
      );
    }
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

  Future<void> _editDisplayName() async {
    final TextEditingController controller = TextEditingController(text: _displayName ?? _username);
    final RegExp validCharacters = RegExp(r'^[a-zA-Z0-9_\-\.\s]+$');
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    bool isValidName(String name) {
      final trimmedName = name.trim();
      return trimmedName.length >= 3 &&
          trimmedName.length <= 14 &&
          validCharacters.hasMatch(name);
    }

    final String? newDisplayName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text('Edit Display Name'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Enter your display name',
              helperText: '- 3-14 characters\n- no special characters',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (isValidName(controller.text)) {
                  Navigator.pop(context, controller.text);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please enter a valid display name (3-14 characters, using only letters, numbers, and _-.).',
                      ),
                    ),
                  );
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );

    if (newDisplayName != null && newDisplayName.isNotEmpty && isValidName(newDisplayName)) {
      setState(() {
        _isEditingDisplayName = true; // Show spinner
      });

      try {
        final client = Provider.of<Client>(context, listen: false);
        final id = client.userID ?? '';
        if (id.isNotEmpty) {
          await client.setDisplayName(id, newDisplayName);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('displayName', newDisplayName);
        }

        setState(() {
          _displayName = newDisplayName;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Display name updated successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update display name: $e')),
        );
      } finally {
        setState(() {
          _isEditingDisplayName = false; // Hide spinner
        });
      }
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
        print("Account successfully deleted.");
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
            _buildAvatar(_username ?? 'Unknown User'),
            SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final textSpan = TextSpan(
                  text: _displayName ?? 'Unknown User',
                  style: TextStyle(
                    fontSize: 20,
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                );
                final textPainter = TextPainter(
                  text: textSpan,
                  textDirection: TextDirection.ltr,
                );
                textPainter.layout();
                return Container(
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          _displayName ?? 'Unknown User',
                          style: TextStyle(
                            fontSize: 20,
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Positioned(
                        left: (constraints.maxWidth / 2) + (textPainter.width / 2) + 8,
                        top: 4,
                        child: _isEditingDisplayName
                            ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        )
                            : GestureDetector(
                          onTap: _editDisplayName,
                          child: Icon(
                            Icons.edit,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),

                    ],
                  ),
                );
              },
            ),
            Text(
              '@$_username',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.normal,
              ),
            ),
            Divider(height: 16),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.visibility_off,
                        color: _incognitoMode
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Incognito Mode',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'Stop sharing location.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Switch(
                    value: _incognitoMode,
                    onChanged: _toggleIncognitoMode,
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                ],
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
                  /*
                  TODO: reimplement clear cache
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
                  */
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
