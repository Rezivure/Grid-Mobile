import 'dart:convert';

class Room {
  final String roomId;
  final String name;
  final bool isGroup; // `false` for direct rooms, `true` for group rooms
  final String lastActivity; // ISO 8601 String for the last activity timestamp
  final String? avatarUrl; // Optional URL for room/group icon
  final List<String> members; // List of user IDs in the room
  final int expirationTimestamp; // Timestamp for expiration, 0 if never expires

  Room({
    required this.roomId,
    required this.name,
    required this.isGroup,
    required this.lastActivity,
    this.avatarUrl,
    required this.members,
    required this.expirationTimestamp,
  });

  // Factory constructor to create an instance from a database map
  factory Room.fromMap(Map<String, dynamic> map) {
    // Handle members field - it might be corrupted as a plain string
    List<String> membersList;
    try {
      final membersData = map['members'];
      if (membersData is String) {
        // Try to parse as JSON
        if (membersData.startsWith('[')) {
          membersList = (jsonDecode(membersData) as List<dynamic>).cast<String>();
        } else {
          // Corrupted data - single user ID as string
          // Convert to list with single member
          print("Warning: Corrupted members field in room ${map['roomId']}: $membersData");
          membersList = [membersData];
        }
      } else {
        // Already a list somehow
        membersList = (membersData as List<dynamic>).cast<String>();
      }
    } catch (e) {
      print("Error parsing members field for room ${map['roomId']}: ${map['members']} - $e");
      membersList = [];
    }
    
    return Room(
      roomId: map['roomId'] as String,
      name: map['name'] as String,
      isGroup: map['isGroup'] == 1, // SQLite stores boolean as 0 or 1
      lastActivity: map['lastActivity'] as String,
      avatarUrl: map['avatarUrl'] as String?,
      members: membersList,
      expirationTimestamp: map['expirationTimestamp'] as int,
    );
  }

  // Method to convert the model to a map for database insertion
  Map<String, dynamic> toMap() {
    return {
      'roomId': roomId,
      'name': name,
      'isGroup': isGroup ? 1 : 0, // SQLite uses 0/1 for booleans
      'lastActivity': lastActivity,
      'avatarUrl': avatarUrl,
      'members': jsonEncode(members),
      'expirationTimestamp': expirationTimestamp,
    };
  }

  Room copyWith({
    String? roomId,
    String? name,
    bool? isGroup,
    String? lastActivity,
    String? avatarUrl,
    List<String>? members,
    int? expirationTimestamp,
  }) {
    return Room(
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      isGroup: isGroup ?? this.isGroup,
      lastActivity: lastActivity ?? this.lastActivity,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      members: members ?? List.from(this.members),
      expirationTimestamp: expirationTimestamp ?? this.expirationTimestamp,
    );
  }

  // Method to serialize the room object to JSON
  String toJson() => jsonEncode(toMap());

  // Factory method to deserialize a room object from JSON
  factory Room.fromJson(String source) =>
      Room.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
