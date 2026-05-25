import 'package:shared_preferences/shared_preferences.dart';

/// Tracks per-user cooldowns for opportunistic avatar/location nudge requests.
///
/// All timestamps are epoch milliseconds in SharedPreferences. Designed to be
/// instantiated ad-hoc (cheap; SharedPreferences itself is a singleton under
/// the hood) so callers don't need DI plumbing.
class RequestCooldownService {
  // Outgoing-request cooldowns (we asked someone for X recently, don't re-ask).
  static const Duration _avatarRequestCooldown = Duration(hours: 24);
  static const Duration _locationRequestCooldown = Duration(hours: 6);
  // Longer cooldown when responder explicitly told us they have no avatar set.
  static const Duration _avatarAbsentCooldown = Duration(days: 7);

  // Incoming-response throttles (we just answered someone, don't re-answer).
  static const Duration _avatarRespondCooldown = Duration(hours: 1);
  static const Duration _locationRespondCooldown = Duration(minutes: 30);

  String _avReqKey(String userId) => 'nudge_avreq_$userId';
  String _locReqKey(String userId) => 'nudge_locreq_$userId';
  String _avRespKey(String senderId) => 'nudge_avresp_$senderId';
  String _locRespKey(String senderId) => 'nudge_locresp_$senderId';
  String _avAbsentKey(String userId) => 'nudge_avabsent_$userId';

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<bool> _isPastCooldown(String key, Duration cooldown) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(key);
    if (last == null) return true;
    return _now() - last >= cooldown.inMilliseconds;
  }

  Future<void> _stamp(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, _now());
  }

  /// True if we may request the avatar from [userId] now.
  Future<bool> shouldRequestAvatar(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final absentAt = prefs.getInt(_avAbsentKey(userId));
    if (absentAt != null &&
        _now() - absentAt < _avatarAbsentCooldown.inMilliseconds) {
      return false;
    }
    return _isPastCooldown(_avReqKey(userId), _avatarRequestCooldown);
  }

  /// True if we may request the location from [userId] now.
  Future<bool> shouldRequestLocation(String userId) async {
    return _isPastCooldown(_locReqKey(userId), _locationRequestCooldown);
  }

  Future<void> markAvatarRequested(String userId) async {
    await _stamp(_avReqKey(userId));
  }

  Future<void> markLocationRequested(String userId) async {
    await _stamp(_locReqKey(userId));
  }

  /// Record that [userId] told us they have no avatar set. Suppresses
  /// further avatar requests until the absent cooldown expires.
  Future<void> markAvatarAbsent(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_avAbsentKey(userId), _now());
    await prefs.setInt(_avReqKey(userId), _now());
  }

  /// True if we have not responded to an avatar request from [senderId]
  /// within the response throttle window.
  Future<bool> shouldRespondToAvatarRequest(String senderId) async {
    return _isPastCooldown(_avRespKey(senderId), _avatarRespondCooldown);
  }

  /// True if we have not responded to a location request from [senderId]
  /// within the response throttle window.
  Future<bool> shouldRespondToLocationRequest(String senderId) async {
    return _isPastCooldown(_locRespKey(senderId), _locationRespondCooldown);
  }

  Future<void> markAvatarResponded(String senderId) async {
    await _stamp(_avRespKey(senderId));
  }

  Future<void> markLocationResponded(String senderId) async {
    await _stamp(_locRespKey(senderId));
  }
}
