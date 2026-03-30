/// Platform-agnostic location data model.
/// This is what the rest of the app uses - no dependency on any plugin types.
class LocationUpdate {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final double heading;
  final double altitude;
  final DateTime timestamp;
  final bool isMoving;

  const LocationUpdate({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.altitude,
    required this.timestamp,
    required this.isMoving,
  });

  /// Create a LocationUpdate from a map (for serialization).
  factory LocationUpdate.fromMap(Map<String, dynamic> map) {
    return LocationUpdate(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
      altitude: (map['altitude'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num).toInt(),
      ),
      isMoving: map['isMoving'] as bool? ?? false,
    );
  }

  /// Convert to a map (for serialization).
  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'altitude': altitude,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isMoving': isMoving,
    };
  }

  LocationUpdate copyWith({
    double? latitude,
    double? longitude,
    double? accuracy,
    double? speed,
    double? heading,
    double? altitude,
    DateTime? timestamp,
    bool? isMoving,
  }) {
    return LocationUpdate(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      altitude: altitude ?? this.altitude,
      timestamp: timestamp ?? this.timestamp,
      isMoving: isMoving ?? this.isMoving,
    );
  }

  @override
  String toString() =>
      'LocationUpdate(lat: $latitude, lng: $longitude, acc: ${accuracy}m, moving: $isMoving)';
}