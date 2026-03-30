import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton debug logging service that POSTs structured JSON to a remote endpoint.
/// All network calls are fire-and-forget and silently swallow errors.
class DebugLogService {
  static final instance = DebugLogService._();
  DebugLogService._();

  String? _endpoint;
  bool _enabled = false;

  bool get enabled => _enabled;
  String? get endpoint => _endpoint;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('debug_log_enabled') ?? false;
      _endpoint = prefs.getString('debug_log_endpoint') ?? 'http://100.83.161.78:9999/logs';
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('debug_log_enabled', enabled);
    } catch (_) {}
  }

  Future<void> setEndpoint(String endpoint) async {
    _endpoint = endpoint;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('debug_log_endpoint', endpoint);
    } catch (_) {}
  }

  /// Fire-and-forget log. Never throws.
  void log(String type, Map<String, dynamic> data) {
    if (!_enabled || _endpoint == null || _endpoint!.isEmpty) return;
    _post(type, data);
  }

  Future<void> _post(String type, Map<String, dynamic> data) async {
    try {
      final body = jsonEncode({
        'type': type,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        ...data,
      });
      await http.post(
        Uri.parse(_endpoint!),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Silent failure — debug logging must never crash the app
    }
  }

  /// Send a test log and return whether it succeeded.
  Future<bool> testConnection() async {
    if (_endpoint == null || _endpoint!.isEmpty) return false;
    try {
      final body = jsonEncode({
        'type': 'test',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'message': 'Test connection from Grid Mobile',
      });
      final response = await http.post(
        Uri.parse(_endpoint!),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
