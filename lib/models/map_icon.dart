import 'package:latlong2/latlong.dart';

class MapIcon {
  final String id;
  final String roomId; // Group or DM room ID
  final String creatorId; // User who placed the icon
  final double latitude;
  final double longitude;
  final String iconType; // 'icon' or 'svg'
  final String iconData; // Icon name (for icons) or SVG data (for SVGs)
  final String? name; // Optional name/title
  final String? description; // Optional description
  final DateTime createdAt;
  final DateTime? expiresAt; // Optional expiration time
  final Map<String, dynamic>? metadata; // Additional data like color, size, etc.

  MapIcon({
    required this.id,
    required this.roomId,
    required this.creatorId,
    required this.latitude,
    required this.longitude,
    required this.iconType,
    required this.iconData,
    this.name,
    this.description,
    required this.createdAt,
    this.expiresAt,
    this.metadata,
  });

  LatLng get position => LatLng(latitude, longitude);

  factory MapIcon.fromJson(Map<String, dynamic> json) {
    return MapIcon(
      id: json['id'],
      roomId: json['room_id'],
      creatorId: json['creator_id'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      iconType: json['icon_type'],
      iconData: json['icon_data'],
      name: json['name'],
      description: json['description'],
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
      metadata: json['metadata'] != null ? Map<String, dynamic>.from(json['metadata']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'creator_id': creatorId,
      'latitude': latitude,
      'longitude': longitude,
      'icon_type': iconType,
      'icon_data': iconData,
      'name': name,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory MapIcon.fromDatabase(Map<String, dynamic> map) {
    return MapIcon(
      id: map['id'],
      roomId: map['room_id'],
      creatorId: map['creator_id'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      iconType: map['icon_type'],
      iconData: map['icon_data'],
      name: map['name'],
      description: map['description'],
      createdAt: DateTime.parse(map['created_at']),
      expiresAt: map['expires_at'] != null ? DateTime.parse(map['expires_at']) : null,
      metadata: map['metadata'] != null ? Map<String, dynamic>.from(map['metadata']) : null,
    );
  }

  Map<String, dynamic> toDatabase() {
    return {
      'id': id,
      'room_id': roomId,
      'creator_id': creatorId,
      'latitude': latitude,
      'longitude': longitude,
      'icon_type': iconType,
      'icon_data': iconData,
      'name': name,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'metadata': metadata?.toString(),
    };
  }
}