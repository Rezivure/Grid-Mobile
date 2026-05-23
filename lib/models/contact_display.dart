class ContactDisplay {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String lastSeen;
  final DateTime? lastUpdateAt;
  final String? membershipStatus;

  ContactDisplay({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.lastSeen,
    this.lastUpdateAt,
    this.membershipStatus,
  });
}
