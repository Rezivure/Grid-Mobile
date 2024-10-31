import 'dart:convert';

class SharingPreferences {
  final String userId;
  final bool activeSharing;
  final bool approvedKeys;
  final List<dynamic> sharePeriods;

  SharingPreferences({
    required this.userId,
    required this.activeSharing,
    required this.approvedKeys,
    required this.sharePeriods,
  });

  // Factory constructor to create an instance from a database map
  factory SharingPreferences.fromMap(Map<String, dynamic> map) {
    return SharingPreferences(
      userId: map['userId'] as String,
      activeSharing: map['activeSharing']?.toString().toLowerCase() == 'true',
      approvedKeys: map['approvedKeys']?.toString().toLowerCase() == 'true',
      sharePeriods: jsonDecode(map['sharePeriods'] as String) as List<dynamic>,
    );
  }

  // Convert the model to a map for database insertion
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'activeSharing': activeSharing.toString(), // Store as TEXT
      'approvedKeys': approvedKeys.toString(),   // Store as TEXT
      'sharePeriods': jsonEncode(sharePeriods),  // Encode JSON for storage
    };
  }


}
