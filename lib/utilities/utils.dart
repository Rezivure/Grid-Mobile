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

/// Utility function to check if a room is a direct room based on its name.
/// Assumes direct room names follow the format: "Grid:Direct:<user1>:<user2>"
bool isDirectRoom(String roomName) {
  // Check if the room name starts with "Grid:Direct:"
  if (!roomName.startsWith("Grid:Direct:")) {
    return false;
  }

  // Extract the remaining part after "Grid:Direct:"
  final remainingPart = roomName.substring("Grid:Direct:".length);

  // Split the remaining part into users by ":"
  final userParts = remainingPart.split(':');

  // Check if there are exactly two user identifiers
  return userParts.length == 4;
}

/// Utility to extract expiration timestamp from a room name.
/// Room name format: "Grid:Group:<expirationTimestamp>:<groupName>:<creatorId>"
/// Returns 0 if the room never expires or the format is invalid.
int extractExpirationTimestamp(String roomName) {
  final parts = roomName.split(':');

  if (parts.length < 3) {
    // If the room name doesn't have enough parts, assume no expiration.
    return 0;
  }

  if (parts[0] == 'Grid' && parts[1] == 'Group') {
    final expirationPart = parts[2];
    return int.tryParse(expirationPart) ?? 0; // Default to 0 if parsing fails.
  }

  // Return 0 if the room is not a group or the format is invalid.
  return 0;
}

