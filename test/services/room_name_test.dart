import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:grid_frontend/utilities/utils.dart';

void main() {
  setUpAll(() {
    // Initialize dotenv with test values so utils functions work
    dotenv.testLoad(fileInput: 'HOMESERVER=matrix.mygrid.app');
  });

  group('isDirectRoom()', () {
    test('valid direct room name returns true', () {
      // Format: Grid:Direct:@user1:server.com:@user2:server.com
      // After "Grid:Direct:", split by ":" gives 4 parts: @user1, server.com, @user2, server.com
      expect(isDirectRoom('Grid:Direct:@alice:matrix.org:@bob:matrix.org'), true);
    });

    test('group room name returns false', () {
      expect(isDirectRoom('Grid:Group:1700000000:MyGroup:@admin:m.org'), false);
    });

    test('empty string returns false', () {
      expect(isDirectRoom(''), false);
    });

    test('non-Grid room returns false', () {
      expect(isDirectRoom('Some Random Room'), false);
    });

    test('partial Grid:Direct prefix returns false', () {
      expect(isDirectRoom('Grid:Direct:'), false);
    });

    test('Grid:Direct with wrong number of parts returns false', () {
      // Only 2 parts after prefix instead of 4
      expect(isDirectRoom('Grid:Direct:@alice:matrix.org'), false);
    });
  });

  group('extractExpirationTimestamp()', () {
    test('valid group room with expiration', () {
      expect(
        extractExpirationTimestamp('Grid:Group:1700000000:MyGroup:@admin:m.org'),
        1700000000,
      );
    });

    test('group room with 0 expiration (never expires)', () {
      expect(
        extractExpirationTimestamp('Grid:Group:0:PermanentGroup:@admin:m.org'),
        0,
      );
    });

    test('direct room returns 0', () {
      expect(
        extractExpirationTimestamp('Grid:Direct:@alice:m.org:@bob:m.org'),
        0,
      );
    });

    test('malformed name with too few parts returns 0', () {
      expect(extractExpirationTimestamp('Grid'), 0);
      expect(extractExpirationTimestamp(''), 0);
    });

    test('non-numeric expiration returns 0', () {
      expect(
        extractExpirationTimestamp('Grid:Group:notanumber:Name:@user:m.org'),
        0,
      );
    });
  });

  group('Room name format conventions', () {
    test('direct room name contains both user IDs', () {
      const name = 'Grid:Direct:@alice:matrix.org:@bob:matrix.org';
      expect(name.startsWith('Grid:Direct:'), true);
      expect(name.contains('@alice:matrix.org'), true);
      expect(name.contains('@bob:matrix.org'), true);
    });

    test('group room name contains expiration, group name, and creator', () {
      const name = 'Grid:Group:1700000000:WeekendTrip:@admin:matrix.org';
      final parts = name.split(':');
      expect(parts[0], 'Grid');
      expect(parts[1], 'Group');
      expect(int.tryParse(parts[2]), 1700000000); // expiration
      expect(parts[3], 'WeekendTrip'); // group name
      expect(parts.sublist(4).join(':'), '@admin:matrix.org'); // creator
    });
  });

  group('localpart()', () {
    test('extracts localpart from full Matrix ID', () {
      expect(localpart('@alice:matrix.org'), 'alice');
    });

    test('handles ID without @ prefix', () {
      expect(localpart('alice:matrix.org'), 'alice');
    });

    test('handles ID with no domain', () {
      expect(localpart('@alice'), 'alice');
    });
  });

  group('parseGroupName()', () {
    test('extracts group name from standard format', () {
      expect(parseGroupName('Grid Group MyTrip with @alice'), 'MyTrip');
    });

    test('returns truncated name for non-standard format', () {
      final result = parseGroupName('Some Random Long Room Name Here');
      expect(result.length, lessThanOrEqualTo(12));
    });

    test('returns full name if short and non-standard', () {
      expect(parseGroupName('Short'), 'Short');
    });
  });

  group('formatUserId()', () {
    // Note: formatUserId depends on dotenv which may not be loaded in tests.
    // It falls back to FALLBACK_DEFAULT_HOMESERVER = 'matrix.mygrid.app'

    test('strips domain for default homeserver', () {
      final result = formatUserId('@alice:matrix.mygrid.app');
      expect(result, '@alice');
    });

    test('keeps full ID for custom homeserver', () {
      final result = formatUserId('@alice:custom.server.com');
      expect(result, '@alice:custom.server.com');
    });

    test('returns malformed ID as-is', () {
      expect(formatUserId('nodomainuser'), 'nodomainuser');
    });
  });

  group('isCustomHomeserver()', () {
    test('default homeserver returns false', () {
      expect(isCustomHomeserver('matrix.mygrid.app'), false);
    });

    test('default with https:// prefix returns false', () {
      expect(isCustomHomeserver('https://matrix.mygrid.app'), false);
    });

    test('default with port 443 returns false', () {
      expect(isCustomHomeserver('https://matrix.mygrid.app:443'), false);
    });

    test('custom homeserver returns true', () {
      expect(isCustomHomeserver('https://my.custom.server'), true);
    });

    test('empty string returns false', () {
      expect(isCustomHomeserver(''), false);
    });

    test('null-like string returns false', () {
      expect(isCustomHomeserver('null'), false);
    });
  });

  group('timeAgo()', () {
    test('seconds ago', () {
      final result = timeAgo(DateTime.now().subtract(const Duration(seconds: 30)));
      expect(result, contains('s ago'));
    });

    test('minutes ago', () {
      final result = timeAgo(DateTime.now().subtract(const Duration(minutes: 5)));
      expect(result, '5m ago');
    });

    test('hours ago', () {
      final result = timeAgo(DateTime.now().subtract(const Duration(hours: 3)));
      expect(result, '3h ago');
    });

    test('days ago', () {
      final result = timeAgo(DateTime.now().subtract(const Duration(days: 2)));
      expect(result, '2d ago');
    });
  });
}
