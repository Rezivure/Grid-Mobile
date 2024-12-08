import 'dart:convert';

class User {
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String lastSeen;
  final String? profileStatus;

  User({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    required this.lastSeen,
    this.profileStatus,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      userId: map['userId'] as String,
      displayName: map['displayName'] as String?,
      avatarUrl: map['avatarUrl'] as String?,
      lastSeen: map['lastSeen'] as String,
      profileStatus: map['profileStatus'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'lastSeen': lastSeen,
      'profileStatus': profileStatus,
    };
  }

  String toJson() => jsonEncode(toMap());

  factory User.fromJson(String source) =>
      User.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
