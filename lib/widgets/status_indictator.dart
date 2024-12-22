
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utilities/time_ago_formatter.dart';

class StatusIndicator extends StatelessWidget {
  final String timeAgo;
  final String? membershipStatus;

  const StatusIndicator({
    Key? key,
    required this.timeAgo,
    this.membershipStatus,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Handle membership status first
    if (membershipStatus == 'invite') {
      return Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Invitation Sent',
            style: TextStyle(color: colorScheme.onSurface),
          ),
        ],
      );
    }

    // Handle regular time ago status
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: TimeAgoFormatter.getStatusColor(timeAgo, colorScheme),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          timeAgo,
          style: TextStyle(color: colorScheme.onSurface),
        ),
      ],
    );
  }
}
