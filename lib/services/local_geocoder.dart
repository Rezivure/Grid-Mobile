import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// On-device, fully offline reverse geocoding from a bundled GeoNames
/// cities500 dataset. Zero network calls.
class LocalGeocoder {
  LocalGeocoder._();
  static final LocalGeocoder instance = LocalGeocoder._();

  static const String _assetPath = 'assets/geocoder/cities500.bin.gz';
  static const int _headerSize = 16;
  static const int _recordSize = 14;
  static const int _lruCapacity = 100;

  Future<void>? _loading;
  bool _ready = false;
  int _count = 0;
  Int32List _lat = Int32List(0);
  Int32List _lng = Int32List(0);
  Uint32List _nameOff = Uint32List(0);
  Uint16List _popLog = Uint16List(0);
  Uint8List _strtab = Uint8List(0);

  final Map<String, String?> _lru = <String, String?>{};

  Future<void> _load() {
    return _loading ??= _doLoad();
  }

  Future<void> _doLoad() async {
    final raw = await rootBundle.load(_assetPath);
    final gz = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    final decoded = Uint8List.fromList(GZipCodec().decode(gz));
    final bd = ByteData.sublistView(decoded);
    if (decoded.length < _headerSize ||
        decoded[0] != 0x47 ||
        decoded[1] != 0x43 ||
        decoded[2] != 0x54 ||
        decoded[3] != 0x32) {
      throw StateError('Invalid geocoder asset header');
    }
    _count = bd.getUint32(4, Endian.little);
    final strOff = bd.getUint32(8, Endian.little);
    _lat = Int32List(_count);
    _lng = Int32List(_count);
    _nameOff = Uint32List(_count);
    _popLog = Uint16List(_count);
    var off = _headerSize;
    for (var i = 0; i < _count; i++) {
      _lat[i] = bd.getInt32(off, Endian.little);
      _lng[i] = bd.getInt32(off + 4, Endian.little);
      _nameOff[i] = bd.getUint32(off + 8, Endian.little);
      _popLog[i] = bd.getUint16(off + 12, Endian.little);
      off += _recordSize;
    }
    _strtab = Uint8List.sublistView(decoded, strOff);
    _ready = true;
  }

  /// Returns a short place label (e.g. "Washington, DC" or "Paris, FR")
  /// for the given coordinates. Returns null if no reasonable match is
  /// found (e.g. open ocean far from any city).
  Future<String?> lookup(double lat, double lng) async {
    final key = _key(lat, lng);
    if (_lru.containsKey(key)) {
      final v = _lru.remove(key);
      _lru[key] = v;
      return v;
    }
    if (!_ready) {
      await _load();
    }
    final result = _nearest(lat, lng);
    _put(key, result);
    return result;
  }

  String _key(double lat, double lng) {
    final a = (lat * 1000).round();
    final b = (lng * 1000).round();
    return '$a,$b';
  }

  void _put(String key, String? value) {
    _lru[key] = value;
    if (_lru.length > _lruCapacity) {
      _lru.remove(_lru.keys.first);
    }
  }

  String? _nearest(double qLat, double qLng) {
    if (_count == 0) return null;
    final qLatE5 = (qLat * 1e5).round();
    final qLngE5 = (qLng * 1e5).round();
    final cosLat = math.cos(qLat * math.pi / 180.0);
    var bestScore = double.infinity;
    var bestIdx = -1;
    var bestRawSq = double.infinity;
    const windowE5 = 300000;
    var lo = _lowerBound(qLatE5 - windowE5);
    var hi = _upperBound(qLatE5 + windowE5);
    if (lo >= hi) {
      lo = 0;
      hi = _count;
    }
    // Pop boost pulls big cities ~30km closer per log decade above 1k pop.
    const popBoostKm = 8.0;
    for (var i = lo; i < hi; i++) {
      final dLat = (_lat[i] - qLatE5).toDouble();
      var dLngRaw = (_lng[i] - qLngE5).toDouble();
      if (dLngRaw > 18000000) dLngRaw -= 36000000;
      if (dLngRaw < -18000000) dLngRaw += 36000000;
      final dLng = dLngRaw * cosLat;
      final sq = dLat * dLat + dLng * dLng;
      // 1 deg ≈ 111 km, 1e5 e5-units ≈ 111 km → sq -> km via sqrt(sq)/900.
      final km = math.sqrt(sq) / 900.0;
      final pop = _popLog[i] / 1000.0;
      final score = km - popBoostKm * pop;
      if (score < bestScore) {
        bestScore = score;
        bestIdx = i;
        bestRawSq = sq;
      }
    }
    if (bestIdx < 0) return null;
    // Reject impossibly far matches (>500km raw distance).
    if (bestRawSq > 2.0e11) return null;
    return _format(bestIdx);
  }

  int _lowerBound(int latE5) {
    var lo = 0, hi = _count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_lat[mid] < latE5) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int _upperBound(int latE5) {
    var lo = 0, hi = _count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_lat[mid] <= latE5) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  String? _format(int idx) {
    var off = _nameOff[idx];
    if (off >= _strtab.length) return null;
    final nameLen = _strtab[off];
    off += 1;
    final name = String.fromCharCodes(_strtab, off, off + nameLen);
    off += nameLen;
    final cc = String.fromCharCodes(_strtab, off, off + 2).trim();
    off += 2;
    final adminLen = _strtab[off];
    off += 1;
    final admin1 = String.fromCharCodes(_strtab, off, off + adminLen);
    if (cc == 'US' && admin1.isNotEmpty) {
      return '$name, $admin1';
    }
    if (cc.isNotEmpty) {
      return '$name, $cc';
    }
    return name;
  }
}
