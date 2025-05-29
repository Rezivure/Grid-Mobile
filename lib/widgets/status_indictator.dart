
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
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.orange.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mail_outline,
              size: 12,
              color: Colors.orange,
            ),
            const SizedBox(width: 4),
            Text(
              'Invitation Sent',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    // Get status color and text
    Color statusColor = _getStatusColor(timeAgo, colorScheme);
    IconData statusIcon = _getStatusIcon(timeAgo);
    String enhancedText = _getEnhancedStatusText(timeAgo);

    // Handle regular time ago status with enhanced styling
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: statusColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            size: 12,
            color: statusColor,
          ),
          const SizedBox(width: 4),
          Text(
            enhancedText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String timeAgo, ColorScheme colorScheme) {
    if (timeAgo == 'Just now' || timeAgo.contains('s ago')) {
      return colorScheme.primary; // Use primary green
    } else if (timeAgo.contains('m ago') && !timeAgo.contains('h')) {
      // Extract minutes to check if over 10 minutes
      final minutesMatch = RegExp(r'(\d+)m ago').firstMatch(timeAgo);
      if (minutesMatch != null) {
        final minutes = int.parse(minutesMatch.group(1)!);
        return minutes <= 10 ? colorScheme.primary : Colors.orange;
      }
      return colorScheme.primary;
    } else if (timeAgo.contains('h ago')) {
      return Colors.orange;
    } else if (timeAgo.contains('d ago')) {
      return Colors.red;
    } else {
      return colorScheme.onSurface.withOpacity(0.4);
    }
  }

  IconData _getStatusIcon(String timeAgo) {
    if (timeAgo == 'Just now' || timeAgo.contains('s ago')) {
      return Icons.circle;
    } else if (timeAgo.contains('m ago') && !timeAgo.contains('h')) {
      return Icons.circle;
    } else if (timeAgo.contains('h ago')) {
      return Icons.schedule;
    } else if (timeAgo.contains('d ago')) {
      return Icons.access_time;
    } else {
      return Icons.circle_outlined;
    }
  }

  String _getEnhancedStatusText(String timeAgo) {
    if (timeAgo == 'Just now') {
      return 'Active now';
    } else if (timeAgo.contains('s ago')) {
      return 'Active now';
    } else if (timeAgo.contains('m ago') && !timeAgo.contains('h')) {
      return timeAgo;
    } else if (timeAgo.contains('h ago')) {
      return timeAgo;
    } else if (timeAgo.contains('d ago')) {
      return timeAgo;
    } else {
      return 'Offline';
    }
  }
}
