import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:latlong2/latlong.dart';
import '../utilities/encryption_utils.dart';

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

  LatLng get position => LatLng(latitude, longitude);

  // Factory constructor to create an instance from a database map
  factory UserLocation.fromMap(Map<String, dynamic> map, String encryptionKey) {
    // Convert IV from string to IV object
    final ivObject = encrypt.IV.fromBase64(map['iv'] as String);

    // Decrypt latitude and longitude
    final decryptedLatitude = decryptText(map['latitude'] as String, encryptionKey, ivObject.base64);
    final decryptedLongitude = decryptText(map['longitude'] as String, encryptionKey, ivObject.base64);

    return UserLocation(
      userId: map['userId'] as String,
      latitude: double.parse(decryptedLatitude),
      longitude: double.parse(decryptedLongitude),
      timestamp: map['timestamp'] as String,
      deviceKeys: jsonDecode(map['deviceKeys'] as String),
      iv: map['iv'] as String,
    );
  }

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
