import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/utilities/error_report.dart';

/// The report a user copies out of a passkey failure is the only channel we
/// have once SMS is gone — if it loses the error text, or leaks something it
/// shouldn't, support can't help and the user is stuck.
void main() {
  final ts = DateTime.utc(2026, 8, 22, 14, 3, 11);

  group('buildErrorReport', () {
    test('includes the action, UTC timestamp and raw error', () {
      final report = buildErrorReport(
        action: 'Passkey signup',
        error: Exception('registration ceremony aborted'),
        timestamp: ts,
      );

      expect(report, contains('Action: Passkey signup'));
      expect(report, contains('Time: 2026-08-22T14:03:11.000Z'));
      expect(report, contains('registration ceremony aborted'));
    });

    test('normalises a local timestamp to UTC so reports correlate', () {
      final local = DateTime.utc(2026, 8, 22, 14, 3, 11).toLocal();
      final report = buildErrorReport(
        action: 'Passkey login',
        error: 'boom',
        timestamp: local,
      );

      expect(report, contains('Time: 2026-08-22T14:03:11.000Z'));
    });

    test('includes optional fields when supplied', () {
      final report = buildErrorReport(
        action: 'Passkey signup',
        error: 'boom',
        timestamp: ts,
        username: 'anyabeech',
        appVersion: '2.0.1 (820)',
        platform: 'android',
      );

      expect(report, contains('Username: anyabeech'));
      expect(report, contains('App: 2.0.1 (820)'));
      expect(report, contains('Platform: android'));
    });

    test('omits optional fields rather than rendering "null"', () {
      final report = buildErrorReport(
        action: 'Passkey login',
        error: 'boom',
        timestamp: ts,
      );

      expect(report, isNot(contains('null')));
      expect(report, isNot(contains('Username:')));
      expect(report, isNot(contains('App:')));
      expect(report, isNot(contains('Platform:')));
    });

    test('omits optional fields that are blank or whitespace', () {
      final report = buildErrorReport(
        action: 'Passkey login',
        error: 'boom',
        timestamp: ts,
        username: '   ',
        appVersion: '',
      );

      expect(report, isNot(contains('Username:')));
      expect(report, isNot(contains('App:')));
    });

    test('never silently produces an empty error section', () {
      final report = buildErrorReport(
        action: 'Passkey signup',
        error: '   ',
        timestamp: ts,
      );

      expect(report, contains('(no error message)'));
    });

    test('keeps the error last so a long trace does not bury the metadata', () {
      final report = buildErrorReport(
        action: 'Passkey signup',
        error: 'line one\nline two',
        timestamp: ts,
        username: 'anyabeech',
      );

      expect(report.indexOf('Username:'), lessThan(report.indexOf('Error:')));
      expect(report.trimRight(), endsWith('line two'));
    });
  });

  group('support constants', () {
    test('guidance points at Discord and promises no SMS fallback', () {
      expect(errorReportGuidance.toLowerCase(), contains('discord'));
      expect(errorReportGuidance.toLowerCase(), isNot(contains('sms')));
    });

    test('Discord invite is a real https invite link', () {
      expect(gridDiscordInvite, startsWith('https://discord.gg/'));
    });
  });
}
