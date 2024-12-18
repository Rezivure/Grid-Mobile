import 'package:flutter/material.dart';

class TimeAgoFormatter {
  static String format(String? timestamp) {
    if (timestamp == null || timestamp == 'Offline') {
      return 'Off Grid';
    }

    try {
      final lastSeenDateTime = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now();

      if (lastSeenDateTime.isAfter(now)) {
        print("Warning: Future timestamp detected: $timestamp");
        return 'Off Grid';
      }

      final difference = now.difference(lastSeenDateTime);

      if (difference.inSeconds < 30) {
        return 'Just now';
      } else if (difference.inMinutes < 1) {
        return '${difference.inSeconds}s ago';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return 'Off Grid';
      }
    } catch (e) {
      print("Error parsing timestamp: $e");
      return 'Off Grid';
    }
  }

  static Color getStatusColor(String timeAgoText, ColorScheme colorScheme) {
    if (timeAgoText == 'Off Grid' || timeAgoText == 'Invitation Sent') {
      return colorScheme.onSurface.withOpacity(0.5);
    } else if (timeAgoText.contains('m ago') ||
        timeAgoText.contains('s ago') ||
        timeAgoText == 'Just now') {
      return colorScheme.primary;
    } else if (timeAgoText.contains('h ago')) {
      return Colors.yellow;
    } else {
      return Colors.red;
    }
  }
}