import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

enum LogStreamLevel { verbose, debug, info, warning, error }

class LogStreamEntry {
  const LogStreamEntry({
    required this.time,
    required this.source,
    required this.level,
    required this.message,
  });

  final DateTime time;
  final String source;
  final LogStreamLevel level;
  final String message;
}

/// Singleton that maintains a ring buffer of recent log lines so the
/// in-app "Synapse Logs" viewer can render them. Captures two sources:
///   1. `print()` / `debugPrint()` output via a Zone override installed
///      from `main()` — this covers most of the app's own logging.
///   2. `Logs()` (matrix-dart-sdk) events drained on a 500 ms ticker. The
///      SDK appends its own events to a public `outputEvents` list, so we
///      copy anything new since our last read.
class LogStreamService extends ChangeNotifier {
  LogStreamService._();
  static final LogStreamService instance = LogStreamService._();

  static const int _maxEntries = 5000;

  final List<LogStreamEntry> _entries = [];
  int _matrixCursor = 0;
  Timer? _ticker;
  bool _paused = false;
  bool _started = false;

  List<LogStreamEntry> get entries => List.unmodifiable(_entries);
  bool get paused => _paused;

  /// Idempotent — safe to call multiple times. Bumps the matrix log level
  /// to verbose so decryption / sync chatter is captured.
  void start() {
    if (_started) return;
    _started = true;
    Logs().level = Level.verbose;
    _ticker = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _drainMatrix(),
    );
  }

  void setPaused(bool v) {
    if (_paused == v) return;
    _paused = v;
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// Forward-facing capture used by the print Zone hook in main.dart.
  void capturePrint(String line) {
    if (_paused) return;
    _append(
      LogStreamEntry(
        time: DateTime.now(),
        source: 'app',
        level: _inferAppLevel(line),
        message: line,
      ),
    );
    notifyListeners();
  }

  void _drainMatrix() {
    if (_paused) return;
    final events = Logs().outputEvents;
    // The SDK's list can in theory be replaced; if our cursor is past the
    // current length, the safest reset is to the end of the new list.
    if (_matrixCursor > events.length) {
      _matrixCursor = events.length;
      return;
    }
    if (_matrixCursor == events.length) return;
    var changed = false;
    for (var i = _matrixCursor; i < events.length; i++) {
      final e = events[i];
      final body = StringBuffer(e.title);
      if (e.exception != null) {
        body.write('\n  ${e.exception}');
      }
      _append(
        LogStreamEntry(
          time: DateTime.now(),
          source: 'matrix',
          level: _toLogLevel(e.level),
          message: body.toString(),
        ),
      );
      changed = true;
    }
    _matrixCursor = events.length;
    if (changed) notifyListeners();
  }

  void _append(LogStreamEntry e) {
    _entries.add(e);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  LogStreamLevel _toLogLevel(Level level) {
    switch (level) {
      case Level.wtf:
      case Level.error:
        return LogStreamLevel.error;
      case Level.warning:
        return LogStreamLevel.warning;
      case Level.info:
        return LogStreamLevel.info;
      case Level.debug:
        return LogStreamLevel.debug;
      case Level.verbose:
        return LogStreamLevel.verbose;
    }
  }

  LogStreamLevel _inferAppLevel(String line) {
    final l = line.toLowerCase();
    if (l.contains('error') ||
        l.contains('failed') ||
        l.contains('exception') ||
        l.contains('[error]')) {
      return LogStreamLevel.error;
    }
    if (l.contains('warn')) return LogStreamLevel.warning;
    return LogStreamLevel.info;
  }
}
