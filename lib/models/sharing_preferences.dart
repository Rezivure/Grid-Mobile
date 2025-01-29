import 'dart:convert';

import 'package:grid_frontend/models/sharing_window.dart';

class SharingPreferences {
  final int? id;
  final String targetId;
  final String targetType;
  final bool activeSharing;
  final List<SharingWindow>? shareWindows;

  SharingPreferences({
    this.id,
    required this.targetId,
    required this.targetType,
    required this.activeSharing,
    this.shareWindows,
  });

  // Convert model to a map for database insertion
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'targetId': targetId,
      'targetType': targetType,
      'activeSharing': activeSharing ? 1 : 0,
      // Encode the list of windows as JSON (or null if no windows)
      'sharePeriods': shareWindows != null
          ? jsonEncode(shareWindows!.map((w) => w.toJson()).toList())
          : null,
    };
  }


  factory SharingPreferences.fromMap(Map<String, dynamic> map) {
    // If 'sharePeriods' is not null, decode it and parse each window
    final rawJson = map['sharePeriods'] as String?;
    List<SharingWindow>? windows;
    if (rawJson != null && rawJson.isNotEmpty) {
      final List decoded = jsonDecode(rawJson);
      windows = decoded.map((item) => SharingWindow.fromJson(item)).toList().cast<SharingWindow>();
    }

    return SharingPreferences(
      id: map['id'] as int?,
      targetId: map['targetId'] as String,
      targetType: map['targetType'] as String,
      activeSharing: (map['activeSharing'] as int) == 1,
      shareWindows: windows,
    );
  }
}
