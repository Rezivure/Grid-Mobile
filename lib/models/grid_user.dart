import 'dart:convert';

class GridUser {
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String lastSeen;
  final String? profileStatus;

  GridUser({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    required this.lastSeen,
    this.profileStatus,
  });

  /// Factory method to create a `GridUser` from a map
  factory GridUser.fromMap(Map<String, dynamic> map) {
    return GridUser(
      userId: map['userId'] as String,
      displayName: map['displayName'] as String?,
      avatarUrl: map['avatarUrl'] as String?,
      lastSeen: map['lastSeen'] as String,
      profileStatus: map['profileStatus'] as String?,
    );
  }

  /// Converts a `GridUser` to a map
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'lastSeen': lastSeen,
      'profileStatus': profileStatus,
    };
  }

  /// Converts a `GridUser` to JSON
  String toJson() => jsonEncode(toMap());

  /// Factory method to create a `GridUser` from JSON
  factory GridUser.fromJson(String source) =>
      GridUser.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
