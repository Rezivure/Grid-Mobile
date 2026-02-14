import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/models/contact_display.dart';

void main() {
  group('ContactDisplay', () {
    test('stores all required fields', () {
      final contact = ContactDisplay(
        userId: '@alice:matrix.org',
        displayName: 'Alice',
        lastSeen: '2026-01-01T00:00:00Z',
      );
      expect(contact.userId, '@alice:matrix.org');
      expect(contact.displayName, 'Alice');
      expect(contact.lastSeen, '2026-01-01T00:00:00Z');
    });

    test('optional fields default to null', () {
      final contact = ContactDisplay(
        userId: '@bob:matrix.org',
        displayName: 'Bob',
        lastSeen: 'Offline',
      );
      expect(contact.avatarUrl, isNull);
      expect(contact.membershipStatus, isNull);
    });

    test('stores optional fields when provided', () {
      final contact = ContactDisplay(
        userId: '@charlie:matrix.org',
        displayName: 'Charlie',
        avatarUrl: 'mxc://example.com/avatar',
        lastSeen: '2026-01-01T00:00:00Z',
        membershipStatus: 'invite',
      );
      expect(contact.avatarUrl, 'mxc://example.com/avatar');
      expect(contact.membershipStatus, 'invite');
    });

    test('membership status can be join', () {
      final contact = ContactDisplay(
        userId: '@dave:matrix.org',
        displayName: 'Dave',
        lastSeen: '2026-01-01T00:00:00Z',
        membershipStatus: 'join',
      );
      expect(contact.membershipStatus, 'join');
    });

    test('handles Offline lastSeen', () {
      final contact = ContactDisplay(
        userId: '@eve:matrix.org',
        displayName: 'Eve',
        lastSeen: 'Offline',
      );
      expect(contact.lastSeen, 'Offline');
    });
  });
}
