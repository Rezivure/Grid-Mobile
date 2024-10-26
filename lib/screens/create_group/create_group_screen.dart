// create_group_screen.dart

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/widgets/custom_search_bar.dart';
import 'package:grid_frontend/screens/create_group/group_details_screen.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../providers/room_provider.dart';

class CreateGroupScreen extends StatefulWidget {
  @override
  _CreateGroupScreenState createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  TextEditingController _groupNameController = TextEditingController();
  TextEditingController _memberInputController = TextEditingController();
  List<String> _members = [];
  double _sliderValue = 1;
  bool _isForever = false;
  bool _isProcessing = false;

  // Method to add a member to the group
  void _addMember() async {
    if (_members.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You can only invite up to 5 members.')),
      );
      return;
    }

    String inputUsername = _memberInputController.text.trim();
    if (inputUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a username.')),
      );
      return;
    }

    String username = inputUsername.startsWith('@') ? inputUsername.substring(1) : inputUsername;

    if (_members.contains(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User already added.')),
      );
      return;
    }

    final roomProvider = Provider.of<RoomProvider>(context, listen: false);
    final doesExist = await roomProvider.userExists('@$username:${dotenv.env['HOMESERVER']}');

    if (!doesExist) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid username: @$username')),
      );
      return;
    } else {
      setState(() {
        _members.add(username);
        _memberInputController.clear();
      });
    }
  }

  // Method to remove a member from the group
  void _removeMember(String username) {
    setState(() {
      _members.remove(username);
    });
  }

  // Method to create the group
  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty || _members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a group name and add members.')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final roomProvider = Provider.of<RoomProvider>(context, listen: false);
      final groupName = _groupNameController.text.trim();

      final durationInHours = _isForever ? 0 : _sliderValue.toInt();

      // Proceed with group creation and pass the duration
      await roomProvider.createGroup(groupName, _members, durationInHours, context);

      // Optionally, show a success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Group "$groupName" created successfully.')),
      );

      // Navigate back after creating the group
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating group: $e')),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Create Group'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Group Name Input
            TextField(
              controller: _groupNameController,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Group Name',
                filled: true,
                fillColor: theme.cardColor,
                contentPadding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(height: 20),
            // Circular Slider for Duration
            SleekCircularSlider(
              min: 1,
              max: 72,
              initialValue: _sliderValue,
              appearance: CircularSliderAppearance(
                customWidths: CustomSliderWidths(
                  trackWidth: 4,
                  progressBarWidth: 8,
                  handlerSize: 8,
                ),
                customColors: CustomSliderColors(
                  trackColor: Colors.grey,
                  progressBarColor: colorScheme.primary,
                  dotColor: colorScheme.primary,
                  hideShadow: true,
                ),
                infoProperties: InfoProperties(
                  modifier: (double value) {
                    if (value >= 71) {
                      _isForever = true;
                      return 'Forever';
                    } else {
                      _isForever = false;
                      return '${value.toInt()}h';
                    }
                  },
                  mainLabelStyle: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                startAngle: 270,
                angleRange: 360,
                size: 200,
              ),
              onChange: (value) {
                setState(() {
                  _sliderValue = value >= 71 ? 72 : value;
                });
              },
            ),
            SizedBox(height: 20),
            // Add Member Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _memberInputController,
                    decoration: InputDecoration(
                      prefixText: '@',
                      hintText: 'Enter username',
                      filled: true,
                      fillColor: theme.cardColor,
                      contentPadding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _addMember,
                  child: Text('Add'),
                ),
              ],
            ),
            SizedBox(height: 20),
            // Display Added Members
            if (_members.isNotEmpty)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _members.map((username) {
                  return Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            child: RandomAvatar(
                              username,
                              height: 80,
                              width: 80,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            username,
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => _removeMember(username),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.red,
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            SizedBox(height: 20),
            // Create Group Button
            ElevatedButton(
              onPressed: (_isProcessing ||
                  _members.isEmpty ||
                  _groupNameController.text.trim().isEmpty)
                  ? null
                  : _createGroup,
              child: _isProcessing
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text('Create Group'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
