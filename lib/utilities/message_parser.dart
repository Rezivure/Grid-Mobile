/// Parsed form of an inbound `m.location` event. `gridv: 2` senders
/// include optional accuracy/speed/heading + a battery block; older
/// senders only provide the `geo_uri` so all of those will be null.
class ParsedLocation {
  const ParsedLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.heading,
    this.batteryLevel,
    this.isCharging,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final double? batteryLevel;
  final bool? isCharging;
}

class MessageParser {
  /// Returns null when the event isn't a usable `m.location`. Always
  /// emits at least lat/lng when it succeeds — the additional fields
  /// are best-effort and only populated when the sender is on a
  /// gridv-2-or-later build.
  ParsedLocation? parseLocationMessage(Map<String, dynamic> messageData) {
    try {
      final content = messageData['content'] as Map<String, dynamic>?;
      if (content == null || content['msgtype'] != 'm.location') {
        return null;
      }

      final geoUri = content['geo_uri'] as String?;
      if (geoUri == null || !geoUri.startsWith('geo:')) {
        return null;
      }

      final coords = _parseGeoUri(geoUri);
      if (coords == null) return null;

      // Extras live at the top level of the event content. Each is
      // independently optional; absence = "sender didn't tell us".
      double? accuracy = (content['accuracy'] as num?)?.toDouble();
      double? speed = (content['speed'] as num?)?.toDouble();
      double? heading = (content['heading'] as num?)?.toDouble();

      double? batteryLevel;
      bool? isCharging;
      final battery = content['battery'];
      if (battery is Map) {
        batteryLevel = (battery['level'] as num?)?.toDouble();
        isCharging = battery['charging'] as bool?;
      }

      return ParsedLocation(
        latitude: coords[0],
        longitude: coords[1],
        accuracy: accuracy,
        speed: speed,
        heading: heading,
        batteryLevel: batteryLevel,
        isCharging: isCharging,
      );
    } catch (e) {
      // Don't print — this runs per inbound event and noisy logs are
      // worse than a silently-dropped malformed payload.
      return null;
    }
  }

  List<double>? _parseGeoUri(String geoUri) {
    final parts = geoUri.substring(4).split(',');
    if (parts.length < 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;
    return [lat, lng];
  }
}
