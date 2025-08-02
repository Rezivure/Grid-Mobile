class LocationPoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? accuracy;

  LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestamp.toIso8601String(),
    if (accuracy != null) 'accuracy': accuracy,
  };

  factory LocationPoint.fromJson(Map<String, dynamic> json) => LocationPoint(
    latitude: json['latitude'] as double,
    longitude: json['longitude'] as double,
    timestamp: DateTime.parse(json['timestamp'] as String),
    accuracy: json['accuracy'] as String?,
  );
}

class LocationHistory {
  final String userId;
  final List<LocationPoint> points;
  final DateTime lastUpdated;

  LocationHistory({
    required this.userId,
    required this.points,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'points': points.map((p) => p.toJson()).toList(),
    'lastUpdated': lastUpdated.toIso8601String(),
  };

  factory LocationHistory.fromJson(Map<String, dynamic> json) => LocationHistory(
    userId: json['userId'] as String,
    points: (json['points'] as List)
        .map((p) => LocationPoint.fromJson(p as Map<String, dynamic>))
        .toList(),
    lastUpdated: DateTime.parse(json['lastUpdated'] as String),
  );
}

class LocationHistoryConfig {
  static const int maxDaysToStore = 7;
  static const int minSecondsBetweenPoints = 180; // 3 minutes
  static const double minDistanceMeters = 50.0; // Minimum distance to register new point
  static const int maxPointsPerUser = 3360; // ~1 point every 3 mins for 7 days
}