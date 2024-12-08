import 'dart:convert';

class SharingPreferences {
  final int? id;
  final String targetId; // ID of the user or group
  final String targetType; // Type: 'user' or 'group'
  final bool activeSharing; // Whether sharing is currently active
  final Map<String, dynamic>? sharePeriods; // Custom sharing periods (optional)

  SharingPreferences({
    this.id,
    required this.targetId,
    required this.targetType,
    required this.activeSharing,
    this.sharePeriods,
  });

  // Convert model to a map for database insertion
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'targetId': targetId,
      'targetType': targetType,
      'activeSharing': activeSharing ? 1 : 0, // Convert bool to integer
      'sharePeriods': sharePeriods != null ? jsonEncode(sharePeriods) : null, // Encode as JSON
    };
  }

  // Create an instance from a database map
  factory SharingPreferences.fromMap(Map<String, dynamic> map) {
    return SharingPreferences(
      id: map['id'] as int?,
      targetId: map['targetId'] as String,
      targetType: map['targetType'] as String,
      activeSharing: (map['activeSharing'] as int) == 1, // Convert integer to bool
      sharePeriods: map['sharePeriods'] != null
          ? jsonDecode(map['sharePeriods'] as String) as Map<String, dynamic>
          : null, // Decode JSON if not null
    );
  }
}
