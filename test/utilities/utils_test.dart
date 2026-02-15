import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:grid_frontend/utilities/utils.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'HOMESERVER=matrix.mygrid.app');
  });

  group('getFirstLetter', () {
    test('returns uppercase first letter', () {
      expect(getFirstLetter('alice'), 'A');
    });

    test('strips @ prefix', () {
      expect(getFirstLetter('@bob'), 'B');
    });

    test('returns empty for empty string', () {
      expect(getFirstLetter(''), '');
    });

    test('handles single character', () {
      expect(getFirstLetter('x'), 'X');
    });

    test('handles @ only throws (edge case bug)', () {
      // getFirstLetter strips @ then tries to index empty string
      expect(() => getFirstLetter('@'), throwsA(isA<RangeError>()));
    });
  });

  group('localpart', () {
    test('extracts localpart from full Matrix ID', () {
      expect(localpart('@alice:matrix.org'), 'alice');
    });

    test('handles ID without @ prefix', () {
      expect(localpart('alice:matrix.org'), 'alice');
    });

    test('handles ID with no domain', () {
      expect(localpart('@alice'), 'alice');
    });

    test('handles complex server name', () {
      expect(localpart('@user:sub.domain.example.com'), 'user');
    });
  });

  group('parseGroupName', () {
    test('extracts group name from standard format', () {
      expect(parseGroupName('Grid Group MyTrip with @alice'), 'MyTrip');
    });

    test('extracts group name with spaces', () {
      expect(parseGroupName('Grid Group My Trip with @alice'), 'My Trip');
    });

    test('returns truncated name for non-standard format (> 12 chars)', () {
      expect(parseGroupName('A Very Long Room Name Here'), hasLength(12));
    });

    test('returns full name if short and non-standard', () {
      expect(parseGroupName('Short'), 'Short');
    });

    test('returns exactly 12 chars for 12-char string', () {
      expect(parseGroupName('TwelveChars!'), 'TwelveChars!');
    });

    test('empty string returns empty', () {
      expect(parseGroupName(''), '');
    });
  });

  group('isDirectRoom', () {
    test('valid direct room name', () {
      expect(isDirectRoom('Grid:Direct:@alice:matrix.org:@bob:matrix.org'), true);
    });

    test('group room name returns false', () {
      expect(isDirectRoom('Grid:Group:1700000000:MyGroup:@admin:m.org'), false);
    });

    test('empty string returns false', () {
      expect(isDirectRoom(''), false);
    });

    test('non-Grid room returns false', () {
      expect(isDirectRoom('Random Room'), false);
    });

    test('Grid:Direct with only one user returns false', () {
      expect(isDirectRoom('Grid:Direct:@alice:matrix.org'), false);
    });

    test('Grid:Direct with extra parts returns false', () {
      expect(isDirectRoom('Grid:Direct:@a:m.org:@b:m.org:@c:m.org'), false);
    });
  });

  group('extractExpirationTimestamp', () {
    test('valid group with expiration', () {
      expect(extractExpirationTimestamp('Grid:Group:1700000000:MyGroup:@admin:m.org'), 1700000000);
    });

    test('group with 0 (never expires)', () {
      expect(extractExpirationTimestamp('Grid:Group:0:Name:@admin:m.org'), 0);
    });

    test('direct room returns 0', () {
      expect(extractExpirationTimestamp('Grid:Direct:@a:m.org:@b:m.org'), 0);
    });

    test('too few parts returns 0', () {
      expect(extractExpirationTimestamp('Grid'), 0);
      expect(extractExpirationTimestamp(''), 0);
    });

    test('non-numeric expiration returns 0', () {
      expect(extractExpirationTimestamp('Grid:Group:abc:Name:@user:m.org'), 0);
    });

    test('large timestamp value', () {
      expect(extractExpirationTimestamp('Grid:Group:9999999999:Name:@user:m.org'), 9999999999);
    });
  });

  group('formatUserId', () {
    test('strips domain for default homeserver', () {
      expect(formatUserId('@alice:matrix.mygrid.app'), '@alice');
    });

    test('keeps full ID for custom homeserver', () {
      expect(formatUserId('@alice:custom.server.com'), '@alice:custom.server.com');
    });

    test('returns malformed ID as-is', () {
      expect(formatUserId('nodomainuser'), 'nodomainuser');
    });

    test('handles empty localpart', () {
      expect(formatUserId(':matrix.mygrid.app'), '');
    });
  });

  group('isCustomHomeserver', () {
    test('default homeserver returns false', () {
      expect(isCustomHomeserver('matrix.mygrid.app'), false);
    });

    test('with https:// prefix returns false', () {
      expect(isCustomHomeserver('https://matrix.mygrid.app'), false);
    });

    test('with port 443 returns false', () {
      expect(isCustomHomeserver('https://matrix.mygrid.app:443'), false);
    });

    test('with http:// and port 80 returns false', () {
      expect(isCustomHomeserver('http://matrix.mygrid.app:80'), false);
    });

    test('custom homeserver returns true', () {
      expect(isCustomHomeserver('https://my.custom.server'), true);
    });

    test('empty string returns false', () {
      expect(isCustomHomeserver(''), false);
    });

    test('null string returns false', () {
      expect(isCustomHomeserver('null'), false);
    });
  });

  group('timeAgo', () {
    test('seconds ago', () {
      final result = timeAgo(DateTime.now().subtract(const Duration(seconds: 30)));
      expect(result, contains('s ago'));
    });

    test('minutes ago', () {
      expect(timeAgo(DateTime.now().subtract(const Duration(minutes: 5))), '5m ago');
    });

    test('hours ago', () {
      expect(timeAgo(DateTime.now().subtract(const Duration(hours: 3))), '3h ago');
    });

    test('days ago', () {
      expect(timeAgo(DateTime.now().subtract(const Duration(days: 2))), '2d ago');
    });

    test('0 seconds ago', () {
      expect(timeAgo(DateTime.now()), '0s ago');
    });

    test('exactly 60 minutes = 1h', () {
      expect(timeAgo(DateTime.now().subtract(const Duration(minutes: 60))), '1h ago');
    });

    test('exactly 24 hours = 1d', () {
      expect(timeAgo(DateTime.now().subtract(const Duration(hours: 24))), '1d ago');
    });
  });
}
