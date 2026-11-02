import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/screens/map/grid_map_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _tileSource(String styleJson) {
  final style = jsonDecode(styleJson) as Map<String, dynamic>;
  return style['sources']['protomaps']['url'] as String;
}

void main() {
  group('customPmtilesUrl', () {
    test('wraps a self-hosted URL in the pmtiles:// scheme (issue #343)', () {
      expect(customPmtilesUrl('https://tiles.example.org/world.pmtiles'),
          'pmtiles://https://tiles.example.org/world.pmtiles');
    });

    test('keeps an already prefixed URL as is', () {
      expect(customPmtilesUrl('pmtiles://https://tiles.example.org/a.pmtiles'),
          'pmtiles://https://tiles.example.org/a.pmtiles');
    });

    test('trims whitespace from user input', () {
      expect(customPmtilesUrl('  http://192.168.1.10:8080/a.pmtiles '),
          'pmtiles://http://192.168.1.10:8080/a.pmtiles');
    });

    test('ignores empty or missing URLs', () {
      expect(customPmtilesUrl(null), isNull);
      expect(customPmtilesUrl(''), isNull);
      expect(customPmtilesUrl('   '), isNull);
    });

    test("treats Grid's own map server as the default", () {
      // Older builds and signup saved the default (v1) URL for everyone.
      expect(
          customPmtilesUrl('https://map.mygrid.app/v1/protomaps.pmtiles'),
          isNull);
    });

    test('respects an explicit default choice', () {
      expect(
          customPmtilesUrl('https://tiles.example.org/a.pmtiles',
              mapsUrlType: 'default'),
          isNull);
    });

    test('ignores URLs without a host', () {
      expect(customPmtilesUrl('tiles.pmtiles'), isNull);
    });
  });

  group('buildGridMapStyle tile source', () {
    tearDown(() async {
      SharedPreferences.setMockInitialValues({});
      applySavedMapsUrl(await SharedPreferences.getInstance());
    });

    test('uses the default basemap when nothing is saved', () async {
      SharedPreferences.setMockInitialValues({});
      applySavedMapsUrl(await SharedPreferences.getInstance());
      expect(_tileSource(buildGridMapStyle(dark: false)), defaultPmtilesUrl);
    });

    test('uses the saved self-hosted URL (issue #343)', () async {
      SharedPreferences.setMockInitialValues({
        'maps_url': 'https://tiles.example.org/world.pmtiles',
        'maps_url_type': 'custom',
      });
      applySavedMapsUrl(await SharedPreferences.getInstance());
      expect(_tileSource(buildGridMapStyle(dark: true)),
          'pmtiles://https://tiles.example.org/world.pmtiles');
    });

    test('goes back to the default once the saved URL is cleared', () async {
      SharedPreferences.setMockInitialValues({
        'maps_url': 'https://tiles.example.org/world.pmtiles',
      });
      final prefs = await SharedPreferences.getInstance();
      applySavedMapsUrl(prefs);
      await prefs.remove('maps_url');
      applySavedMapsUrl(prefs);
      expect(_tileSource(buildGridMapStyle(dark: false)), defaultPmtilesUrl);
    });

    test('an explicit pmtilesUrl still wins', () {
      expect(
          _tileSource(buildGridMapStyle(
              dark: false, pmtilesUrl: 'pmtiles://https://x.test/a.pmtiles')),
          'pmtiles://https://x.test/a.pmtiles');
    });
  });
}
