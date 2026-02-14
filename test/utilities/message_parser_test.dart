import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/utilities/message_parser.dart';

void main() {
  late MessageParser parser;

  setUp(() {
    parser = MessageParser();
  });

  group('parseLocationMessage', () {
    test('parses valid location message', () {
      final result = parser.parseLocationMessage({
        'content': {
          'msgtype': 'm.location',
          'geo_uri': 'geo:40.7128,-74.0060',
          'body': 'Location',
        },
      });
      expect(result, isNotNull);
      expect(result!['latitude'], 40.7128);
      expect(result['longitude'], -74.0060);
    });

    test('returns null for non-location message', () {
      final result = parser.parseLocationMessage({
        'content': {
          'msgtype': 'm.text',
          'body': 'Hello',
        },
      });
      expect(result, isNull);
    });

    test('returns null for null content', () {
      final result = parser.parseLocationMessage({
        'content': null,
      });
      expect(result, isNull);
    });

    test('returns null for missing content key', () {
      final result = parser.parseLocationMessage({});
      expect(result, isNull);
    });

    test('returns null for invalid geo_uri format', () {
      final result = parser.parseLocationMessage({
        'content': {
          'msgtype': 'm.location',
          'geo_uri': 'invalid',
        },
      });
      expect(result, isNull);
    });

    test('returns null for null geo_uri', () {
      final result = parser.parseLocationMessage({
        'content': {
          'msgtype': 'm.location',
          'geo_uri': null,
        },
      });
      expect(result, isNull);
    });

    test('returns null for geo_uri with only one coordinate', () {
      final result = parser.parseLocationMessage({
        'content': {
          'msgtype': 'm.location',
          'geo_uri': 'geo:40.7128',
        },
      });
      expect(result, isNull);
    });

    test('parses negative coordinates', () {
      final result = parser.parseLocationMessage({
        'content': {
          'msgtype': 'm.location',
          'geo_uri': 'geo:-33.8688,-151.2093',
        },
      });
      expect(result, isNotNull);
      expect(result!['latitude'], -33.8688);
      expect(result['longitude'], closeTo(-151.2093, 0.0001));
    });

    test('parses zero coordinates', () {
      final result = parser.parseLocationMessage({
        'content': {
          'msgtype': 'm.location',
          'geo_uri': 'geo:0.0,0.0',
        },
      });
      expect(result, isNotNull);
      expect(result!['latitude'], 0.0);
      expect(result['longitude'], 0.0);
    });

    test('handles geo_uri with altitude (third component)', () {
      final result = parser.parseLocationMessage({
        'content': {
          'msgtype': 'm.location',
          'geo_uri': 'geo:40.7128,-74.0060,100',
        },
      });
      // Should still parse lat/lon even with altitude
      expect(result, isNotNull);
      expect(result!['latitude'], 40.7128);
      expect(result['longitude'], -74.0060);
    });

    test('returns null for non-numeric coordinates', () {
      final result = parser.parseLocationMessage({
        'content': {
          'msgtype': 'm.location',
          'geo_uri': 'geo:abc,def',
        },
      });
      expect(result, isNull);
    });

    test('returns null for geo_uri without geo: prefix', () {
      final result = parser.parseLocationMessage({
        'content': {
          'msgtype': 'm.location',
          'geo_uri': '40.7128,-74.0060',
        },
      });
      expect(result, isNull);
    });
  });
}
