import 'dart:convert';

import 'package:grid_frontend/utilities/encryption_utils.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class UserLocation {
  final String userId;
  final double latitude;
  final double longitude;
  final String timestamp;
  final Map<String, dynamic> deviceKeys;
  final String iv; // Store as a String in the database

  UserLocation({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.deviceKeys,
    required this.iv,
  });

  // Convert the model to a map for database insertion, including encryption
  Map<String, dynamic> toMap(String encryptionKey) {
    // Convert IV from string to IV object
    final ivObject = encrypt.IV.fromBase64(iv);

    // Encrypt latitude and longitude
    final encryptedLatitude = encryptText(latitude.toString(), encryptionKey, ivObject);
    final encryptedLongitude = encryptText(longitude.toString(), encryptionKey, ivObject);

    return {
      'userId': userId,
      'latitude': encryptedLatitude,
      'longitude': encryptedLongitude,
      'timestamp': timestamp,
      'deviceKeys': jsonEncode(deviceKeys),
      'iv': iv, // Store the IV as a string in the database
    };
  }
}
