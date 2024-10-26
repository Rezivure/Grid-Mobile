import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:random_avatar/random_avatar.dart';
import '/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/services/location_broadcast_service.dart';
import '/services/location_tracking_service.dart';
import 'package:url_launcher/url_launcher.dart';

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
                    color: Colors.red,
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
