
class MessageParser {
  Map<String, double>? parseLocationMessage(Map<String, dynamic> messageData) {
    try {
      final content = messageData['content'] as Map<String, dynamic>?;
      if (content == null || content['msgtype'] != 'm.location') {
        print('Invalid or non-location message');
        return null;
      }

      final geoUri = content['geo_uri'] as String?;
      if (geoUri == null || !geoUri.startsWith('geo:')) {
        print('Invalid geo_uri format');
        return null;
      }

      final coordinates = _parseGeoUri(geoUri);
      if (coordinates != null) {
        print('Parsed location: $coordinates');
      }
      return coordinates;
    } catch (e) {
      print('Error parsing location message: $e');
      return null;
    }
  }

  Map<String, double>? _parseGeoUri(String geoUri) {
    final parts = geoUri.substring(4).split(',');
    if (parts.length < 2) return null;

    final latitude = double.tryParse(parts[0]);
    final longitude = double.tryParse(parts[1]);

    if (latitude != null && longitude != null) {
      return {'latitude': latitude, 'longitude': longitude};
    }

    return null;
  }
}
