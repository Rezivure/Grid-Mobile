import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/services/message_processor.dart';

/// Unit coverage for the megolm decrypt-failure noise gate. This is the
/// gate that decides whether a failed-decryption event is recent enough
/// to warrant an active key re-request. A previously too-tight 10-minute
/// bound stranded peers whose most-recent location was tens of minutes
/// old, surfacing as "everyone offline" after the v2 upgrade.
void main() {
  group('MessageProcessor.shouldAttemptKeyRecovery', () {
    final now = DateTime.utc(2026, 7, 13, 12, 0, 0);

    test('recovers a very recent failure', () {
      expect(
        MessageProcessor.shouldAttemptKeyRecovery(
            now.subtract(const Duration(seconds: 30)), now),
        isTrue,
      );
    });

    test('recovers a stale-but-recent last location (regression case)', () {
      // 45 minutes old: previously dropped by the 10-minute gate, which is
      // exactly the "everyone offline" bug. Must now recover.
      expect(
        MessageProcessor.shouldAttemptKeyRecovery(
            now.subtract(const Duration(minutes: 45)), now),
        isTrue,
      );
    });

    test('recovers right up to the boundary', () {
      expect(
        MessageProcessor.shouldAttemptKeyRecovery(
            now.subtract(MessageProcessor.keyRecoveryMaxAge), now),
        isTrue,
      );
    });

    test('drops ancient prior-install spam', () {
      expect(
        MessageProcessor.shouldAttemptKeyRecovery(
            now.subtract(const Duration(hours: 6, minutes: 1)), now),
        isFalse,
      );
      expect(
        MessageProcessor.shouldAttemptKeyRecovery(
            now.subtract(const Duration(days: 3)), now),
        isFalse,
      );
    });

    test('treats future-dated (clock-skew) events as recent', () {
      expect(
        MessageProcessor.shouldAttemptKeyRecovery(
            now.add(const Duration(minutes: 5)), now),
        isTrue,
      );
    });
  });
}
