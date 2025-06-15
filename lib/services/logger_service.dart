import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
}

class Logger {
  static bool enableDebugLogs = kDebugMode;
  static LogLevel minimumLogLevel = kDebugMode ? LogLevel.debug : LogLevel.info;
  
  // Deduplication cache to prevent spam
  static final Map<String, DateTime> _recentLogs = {};
  static const Duration _deduplicationWindow = Duration(milliseconds: 100);
  
  // Emojis for different log levels
  static const Map<LogLevel, String> _logEmojis = {
    LogLevel.debug: '🔵',
    LogLevel.info: '🟢',
    LogLevel.warning: '🟡',
    LogLevel.error: '🔴',
  };
  
  static void debug(String tag, String message, {Map<String, dynamic>? data}) {
    _log(LogLevel.debug, tag, message, data: data);
  }
  
  static void info(String tag, String message, {Map<String, dynamic>? data}) {
    _log(LogLevel.info, tag, message, data: data);
  }
  
  static void warning(String tag, String message, {Map<String, dynamic>? data}) {
    _log(LogLevel.warning, tag, message, data: data);
  }
  
  static void error(String tag, String message, {dynamic error, StackTrace? stackTrace, Map<String, dynamic>? data}) {
    _log(LogLevel.error, tag, message, error: error, stackTrace: stackTrace, data: data);
  }
  
  static void _log(
    LogLevel level, 
    String tag, 
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  }) {
    // Check if we should log based on level
    if (level.index < minimumLogLevel.index) return;
    
    // Skip debug logs in release mode
    if (!enableDebugLogs && level == LogLevel.debug) return;
    
    // Deduplicate logs
    final logKey = '$tag:$message';
    if (!_shouldLog(logKey)) return;
    
    // Format the message
    final emoji = _logEmojis[level] ?? '';
    final formattedMessage = '$emoji $message';
    
    // Add data if provided
    final fullMessage = data != null && data.isNotEmpty
        ? '$formattedMessage | ${data.entries.map((e) => '${e.key}: ${e.value}').join(', ')}'
        : formattedMessage;
    
    // Log using dart:developer
    developer.log(
      fullMessage,
      name: tag,
      level: _levelToInt(level),
      error: error,
      stackTrace: stackTrace,
    );
  }
  
  static bool _shouldLog(String key) {
    final now = DateTime.now();
    final lastLogged = _recentLogs[key];
    
    if (lastLogged != null && now.difference(lastLogged) < _deduplicationWindow) {
      return false;
    }
    
    _recentLogs[key] = now;
    
    // Clean up old entries periodically
    if (_recentLogs.length > 1000) {
      _recentLogs.removeWhere((k, v) => 
        now.difference(v) > _deduplicationWindow * 10
      );
    }
    
    return true;
  }
  
  static int _levelToInt(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }
  
  // Utility method to format location logs consistently
  static String formatLocation(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return 'unknown';
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }
  
  // Utility method to truncate long strings
  static String truncate(String text, {int maxLength = 100}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}