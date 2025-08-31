import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class InvitationsRepository {
  static const String _invitationsKey = 'persisted_invitations';

  Future<void> saveInvitations(List<Map<String, dynamic>> invitations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final invitationsJson = jsonEncode(invitations);
      await prefs.setString(_invitationsKey, invitationsJson);
      print('[InvitationsRepository] Saved ${invitations.length} invitations');
    } catch (e) {
      print('[InvitationsRepository] Error saving invitations: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadInvitations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final invitationsJson = prefs.getString(_invitationsKey);
      
      if (invitationsJson == null || invitationsJson.isEmpty) {
        print('[InvitationsRepository] No saved invitations found');
        return [];
      }
      
      final decoded = jsonDecode(invitationsJson) as List<dynamic>;
      final invitations = decoded.map((item) => Map<String, dynamic>.from(item)).toList();
      
      print('[InvitationsRepository] Loaded ${invitations.length} invitations');
      return invitations;
    } catch (e) {
      print('[InvitationsRepository] Error loading invitations: $e');
      return [];
    }
  }

  Future<void> clearInvitations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_invitationsKey);
      print('[InvitationsRepository] Cleared persisted invitations');
    } catch (e) {
      print('[InvitationsRepository] Error clearing invitations: $e');
    }
  }
}