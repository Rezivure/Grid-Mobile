import 'package:flutter/material.dart';

/// Freshness band for a last-seen timestamp, palette-agnostic so callers
/// can map it onto their own theme tokens (and so it's unit-testable).
enum FreshnessBand { fresh, recent, stale, offline }

class TimeAgoFormatter {
  static String format(String? timestamp) {
    if (timestamp == null || timestamp == 'Offline') {
      return 'Offline';
    }

    try {
      final lastSeenDateTime = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now();

      if (lastSeenDateTime.isAfter(now)) {
        print("Warning: Future timestamp detected: $timestamp");
        return 'Offline';
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
        return 'Offline';
      }
    } catch (e) {
      print("Error parsing timestamp: $e");
      return 'Offline';
    }
  }

  /// Pure freshness classifier used to color the last-seen pill. Mirrors
  /// [format]'s thresholds: < 15m fresh, < 1h recent, < 24h stale, else offline.
  static FreshnessBand bandFor(String? timestamp) {
    if (timestamp == null || timestamp == 'Offline') return FreshnessBand.offline;
    try {
      final lastSeen = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now();
      if (lastSeen.isAfter(now)) return FreshnessBand.offline;
      final diff = now.difference(lastSeen);
      if (diff.inMinutes < 15) return FreshnessBand.fresh;
      if (diff.inHours < 1) return FreshnessBand.recent;
      if (diff.inHours < 24) return FreshnessBand.stale;
      return FreshnessBand.offline;
    } catch (_) {
      return FreshnessBand.offline;
    }
  }

  static Color getStatusColor(String timeAgoText, ColorScheme colorScheme) {
    if (timeAgoText == 'Offline' || timeAgoText == 'Invitation Sent') {
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