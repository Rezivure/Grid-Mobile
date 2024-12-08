import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


Color generateColorFromUsername(String username) {
  final random = Random(username.hashCode);

  Color primaryColor =  Color(0xFF00DBA4); // Caribbean Green
  Color secondaryColor = Color(0xFF267373); // Oracle

  // Mix the primary and secondary colors based on the username hash
  double mixFactor = random.nextDouble() * 20;
  Color mixedColor = Color.lerp(primaryColor, secondaryColor, mixFactor)!;

  // Optionally adjust brightness and saturation further
  HSLColor hslColor = HSLColor.fromColor(mixedColor);
  hslColor = hslColor.withLightness(0.6); // Adjust lightness to enhance the professional feel
  hslColor = hslColor.withSaturation(0.5); // Reduce saturation

  return hslColor.toColor();
}

String getFirstLetter(String username) {
  return username.isNotEmpty ? username.replaceAll('@', '')[0].toUpperCase() : '';
}

String parseGroupName(String roomName) {
  const prefix = "Grid Group ";
  const suffix = " with ";

  if (roomName.startsWith(prefix) && roomName.contains(suffix)) {
    final startIndex = prefix.length;
    final endIndex = roomName.indexOf(suffix, startIndex);
    return roomName.substring(startIndex, endIndex);
  }

  // Default case: return the first 12 characters if no prefix/suffix found
  return roomName.length > 12 ? roomName.substring(0, 12) : roomName;
}

String localpart(String userId) {
  return userId.split(":").first.replaceFirst('@', '');
}

/// Converts a `DateTime` into a human-readable "time ago" string.
String timeAgo(DateTime lastSeen) {
  final now = DateTime.now();
  final difference = now.difference(lastSeen);

  if (difference.inSeconds < 60) {
    return '${difference.inSeconds}s ago';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  } else if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  } else {
    return '${difference.inDays}d ago';
  }
}

/// Normalizes a username and constructs a Matrix-compatible user ID.
///
/// Returns a Map with `matrixUserId` and `displayUsername`.
Map<String, String> normalizeUser(String username) {
  // Ensure the username is trimmed and lowercase
  String normalizedUserId = username.trim().toLowerCase();

  // Construct the Matrix-compatible user ID
  String matrixUserId = normalizedUserId.startsWith('@')
      ? normalizedUserId
      : '@$normalizedUserId:${dotenv.env['HOMESERVER']}';

  // Extract the display username
  String displayUsername = normalizedUserId.startsWith('@')
      ? normalizedUserId.substring(1).split(':').first
      : normalizedUserId;

  return {
    'matrixUserId': matrixUserId,
    'displayUsername': displayUsername,
  };
}

