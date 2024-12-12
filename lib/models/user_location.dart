import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:latlong2/latlong.dart';
import 'package:grid_frontend/utilities/encryption_utils.dart';

class UserLocation {
  final String userId;
  final double latitude;
  final double longitude;
  final String timestamp; // ISO 8601 format
  final String iv;

  UserLocation({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.iv,
  });

  // Getter to provide LatLng object for map display
  LatLng get position => LatLng(latitude, longitude);

  /// Factory constructor to create an instance from a database map.
  /// Handles decryption for latitude and longitude.
  factory UserLocation.fromMap(Map<String, dynamic> map, String encryptionKey) {
    final ivString = map['iv'] as String;

    // Decrypt latitude and longitude
    final decryptedLatitude = decryptText(map['latitude'] as String, encryptionKey, ivString);
    final decryptedLongitude = decryptText(map['longitude'] as String, encryptionKey, ivString);

    return UserLocation(
      userId: map['userId'] as String,
      latitude: double.parse(decryptedLatitude),
      longitude: double.parse(decryptedLongitude),
      timestamp: map['timestamp'] as String,
      iv: ivString,
    );
  }

  /// Convert the model to a map for database insertion.
  /// Handles encryption for sensitive fields.
  Map<String, dynamic> toMap(String encryptionKey) {
    final ivObject = encrypt.IV.fromBase64(iv);

    // Encrypt latitude and longitude
    final encryptedLatitude = encryptText(latitude.toString(), encryptionKey, ivObject);
    final encryptedLongitude = encryptText(longitude.toString(), encryptionKey, ivObject);

    return {
      'userId': userId,
      'latitude': encryptedLatitude,
      'longitude': encryptedLongitude,
      'timestamp': timestamp,
      'iv': iv,
    };
  }

  /// Serialize to JSON for API or external usage
  String toJson(String encryptionKey) => jsonEncode(toMap(encryptionKey));

  /// Deserialize from JSON
  factory UserLocation.fromJson(String source, String encryptionKey) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    return UserLocation.fromMap(map, encryptionKey);
  }
}
