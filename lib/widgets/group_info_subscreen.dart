// group_info_subscreen.dart
import 'package:flutter/material.dart';

class GroupInfoSubscreen extends StatelessWidget {
  final String groupName;
  final VoidCallback onBack;
  final ScrollController scrollController;

  GroupInfoSubscreen({
    required this.groupName,
    required this.onBack,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.arrow_back),
          title: Text('Back'),
          onTap: onBack,
        ),
        Text(
          groupName,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: 5, // Mock number of group members, replace with actual data
            itemBuilder: (context, index) {
              return ListTile(
                title: Text('Group Member $index'),
              );
            },
          ),
        ),
      ],
    );
  }
}
