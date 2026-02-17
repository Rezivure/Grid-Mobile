import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/blocs/avatar/avatar_state.dart';

void main() {
  group('AvatarState', () {
    test('default state has empty maps', () {
      const state = AvatarState();
      expect(state.avatarCache, isEmpty);
      expect(state.loadingStates, isEmpty);
      expect(state.lastUpdated, isEmpty);
      expect(state.failedAttempts, isEmpty);
      expect(state.updateCounter, 0);
    });

    test('getAvatar returns cached avatar', () {
      final avatarData = Uint8List.fromList([1, 2, 3]);
      final state = AvatarState(avatarCache: {'user1': avatarData});
      expect(state.getAvatar('user1'), equals(avatarData));
    });

    test('getAvatar returns null for missing user', () {
      const state = AvatarState();
      expect(state.getAvatar('nonexistent'), isNull);
    });

    test('isLoading returns true when loading', () {
      const state = AvatarState(loadingStates: {'user1': true});
      expect(state.isLoading('user1'), isTrue);
    });

    test('isLoading returns false when not loading', () {
      const state = AvatarState(loadingStates: {'user1': false});
      expect(state.isLoading('user1'), isFalse);
    });

    test('isLoading returns false for unknown user', () {
      const state = AvatarState();
      expect(state.isLoading('unknown'), isFalse);
    });

    test('getLastUpdated returns date for known user', () {
      final now = DateTime.now();
      final state = AvatarState(lastUpdated: {'user1': now});
      expect(state.getLastUpdated('user1'), equals(now));
    });

    test('getLastUpdated returns null for unknown user', () {
      const state = AvatarState();
      expect(state.getLastUpdated('unknown'), isNull);
    });

    group('hasRecentlyFailed', () {
      test('returns false for unknown user', () {
        const state = AvatarState();
        expect(state.hasRecentlyFailed('unknown'), isFalse);
      });

      test('returns true for recently failed user', () {
        final state = AvatarState(failedAttempts: {
          'user1': DateTime.now(),
        });
        expect(state.hasRecentlyFailed('user1'), isTrue);
      });

      test('returns false for user that failed long ago', () {
        final state = AvatarState(failedAttempts: {
          'user1': DateTime.now().subtract(const Duration(minutes: 10)),
        });
        expect(state.hasRecentlyFailed('user1'), isFalse);
      });

      test('returns true for user that failed 4 minutes ago', () {
        final state = AvatarState(failedAttempts: {
          'user1': DateTime.now().subtract(const Duration(minutes: 4)),
        });
        expect(state.hasRecentlyFailed('user1'), isTrue);
      });

      test('returns false for user that failed exactly 5 minutes ago', () {
        final state = AvatarState(failedAttempts: {
          'user1': DateTime.now().subtract(const Duration(minutes: 5)),
        });
        expect(state.hasRecentlyFailed('user1'), isFalse);
      });
    });

    group('copyWith', () {
      test('preserves all fields', () {
        final avatarData = Uint8List.fromList([1, 2, 3]);
        final now = DateTime.now();
        final state = AvatarState(
          avatarCache: {'user1': avatarData},
          loadingStates: {'user1': true},
          lastUpdated: {'user1': now},
          failedAttempts: {'user2': now},
          updateCounter: 5,
        );

        final copied = state.copyWith();
        expect(copied.avatarCache['user1'], equals(avatarData));
        expect(copied.loadingStates['user1'], isTrue);
        expect(copied.lastUpdated['user1'], equals(now));
        expect(copied.failedAttempts['user2'], equals(now));
        expect(copied.updateCounter, 5);
      });

      test('overrides specific fields', () {
        const state = AvatarState(updateCounter: 0);
        final newState = state.copyWith(updateCounter: 10);
        expect(newState.updateCounter, 10);
      });

      test('overrides avatar cache', () {
        final state = AvatarState(
          avatarCache: {'user1': Uint8List.fromList([1])},
        );
        final newData = Uint8List.fromList([2, 3]);
        final newState = state.copyWith(avatarCache: {'user2': newData});
        expect(newState.avatarCache.containsKey('user1'), isFalse);
        expect(newState.avatarCache['user2'], equals(newData));
      });
    });

    group('equality', () {
      test('same default states are equal', () {
        const state1 = AvatarState();
        const state2 = AvatarState();
        expect(state1, equals(state2));
      });

      test('different counters are not equal', () {
        const state1 = AvatarState(updateCounter: 1);
        const state2 = AvatarState(updateCounter: 2);
        expect(state1, isNot(equals(state2)));
      });

      test('same avatar data is equal', () {
        final data = Uint8List.fromList([1, 2, 3]);
        final state1 = AvatarState(avatarCache: {'user1': data});
        final state2 = AvatarState(avatarCache: {'user1': data});
        expect(state1, equals(state2));
      });
    });
  });
}
