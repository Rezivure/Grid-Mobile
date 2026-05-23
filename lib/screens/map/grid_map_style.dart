import 'dart:convert';

import 'protomaps_v4_light_layers.dart';
import 'protomaps_v4_dark_layers.dart';

/// Build a MapLibre style JSON for Grid's basemap.
///
/// Renders the V2 protomaps pmtiles via maplibre-native with the full
/// protomaps basemap v4 style (light or dark), plus extra POI layers
/// tuned for a location-sharing app (restaurants, gas stations,
/// hospitals, etc.).
String buildGridMapStyle({
  required bool dark,
  String pmtilesUrl =
      'pmtiles://https://map.mygrid.app/v2/v2_protomaps_20260512.pmtiles',
}) {
  final spriteFlavor = dark ? 'dark' : 'light';
  final style = <String, dynamic>{
    'version': 8,
    'sources': {
      'protomaps': {
        'type': 'vector',
        'url': pmtilesUrl,
        'attribution':
            '<a href="https://protomaps.com">Protomaps</a> © <a href="https://openstreetmap.org">OSM</a>',
      }
    },
    'sprite':
        'https://protomaps.github.io/basemaps-assets/sprites/v4/$spriteFlavor',
    'glyphs':
        'https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf',
    'layers': [
      ...(dark ? protomapsV4DarkLayers : protomapsV4LightLayers),
      ..._extraPoiLayers(dark: dark),
    ],
  };
  return jsonEncode(style);
}

/// Extra POI layers stacked on top of the protomaps base style.
/// Tiered by importance/visibility, drawn in the order returned.
List<Map<String, dynamic>> _extraPoiLayers({required bool dark}) => [
      _poiLayer(
        id: 'pois_grid_emergency',
        minzoom: 13,
        kinds: ['hospital', 'police', 'fire_station'],
        iconSize: 0.95,
        textSize: 11.5,
        dark: dark,
      ),
      _poiLayer(
        id: 'pois_grid_transit_fuel',
        minzoom: 13,
        kinds: [
          'fuel', 'charging_station', 'bus_station', 'train_station',
          'subway_entrance', 'airport',
        ],
        dark: dark,
      ),
      _poiLayer(
        id: 'pois_grid_services',
        minzoom: 14,
        kinds: [
          'school', 'kindergarten', 'college', 'university', 'library',
          'post_office', 'bank', 'atm', 'pharmacy',
          'place_of_worship', 'townhall', 'embassy',
        ],
        dark: dark,
      ),
      _poiLayer(
        id: 'pois_grid_lodging_leisure',
        minzoom: 14,
        kinds: [
          'hotel', 'motel', 'hostel', 'guest_house',
          'cinema', 'theatre', 'museum', 'attraction',
          'art_gallery', 'gallery', 'stadium', 'sports_centre',
        ],
        dark: dark,
      ),
      _poiLayer(
        id: 'pois_grid_dining',
        minzoom: 15,
        kinds: [
          'restaurant', 'cafe', 'fast_food', 'bar', 'pub',
          'food_court', 'biergarten', 'ice_cream', 'bakery',
        ],
        dark: dark,
      ),
      _poiLayer(
        id: 'pois_grid_shopping',
        minzoom: 15,
        kinds: [
          'shop', 'supermarket', 'convenience', 'department_store',
          'mall', 'marketplace', 'florist', 'hairdresser',
          'laundry', 'optician', 'clothes', 'electronics', 'gift',
        ],
        dark: dark,
      ),
      _poiLayer(
        id: 'pois_grid_misc',
        minzoom: 16,
        kinds: [
          'parking', 'toilets', 'drinking_water', 'bench', 'recycling',
          'veterinary', 'doctors', 'clinic', 'dentist',
        ],
        iconSize: 0.75,
        textSize: 10,
        dark: dark,
      ),
    ];

Map<String, dynamic> _poiLayer({
  required String id,
  required int minzoom,
  required List<String> kinds,
  required bool dark,
  double iconSize = 0.85,
  double textSize = 11,
}) {
  return {
    'id': id,
    'type': 'symbol',
    'source': 'protomaps',
    'source-layer': 'pois',
    'minzoom': minzoom,
    'filter': [
      'in',
      ['get', 'kind'],
      ['literal', kinds],
    ],
    'layout': {
      'icon-image': ['get', 'kind'],
      'icon-size': iconSize,
      'icon-allow-overlap': false,
      'icon-optional': false,
      'text-field': [
        'coalesce',
        ['get', 'name:en'],
        ['get', 'name'],
      ],
      'text-font': ['Noto Sans Regular'],
      'text-size': textSize,
      'text-anchor': 'top',
      'text-offset': [0, 1.0],
      'text-optional': true,
      'text-max-width': 7,
    },
    'paint': {
      'text-color': dark ? '#cfcfcf' : '#3b3b3b',
      'text-halo-color': dark ? '#15171a' : '#ffffff',
      'text-halo-width': 1.5,
    },
  };
}
