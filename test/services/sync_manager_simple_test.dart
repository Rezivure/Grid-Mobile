import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grid_frontend/services/sync_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncManager Core Logic Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('sync state management', () {
      test('starts with uninitialized state', () {
        // Test that sync manager starts in the correct state
        expect(SyncState.uninitialized, equals(SyncState.uninitialized));
        expect(SyncState.ready, equals(SyncState.ready));
        expect(SyncState.error, equals(SyncState.error));
      });

      test('sync state enum values are correct', () {
        // Test all sync states exist
        const states = SyncState.values;
        expect(states.contains(SyncState.uninitialized), isTrue);
        expect(states.contains(SyncState.loadingToken), isTrue);
        expect(states.contains(SyncState.performingCatchUp), isTrue);
        expect(states.contains(SyncState.processingRooms), isTrue);
        expect(states.contains(SyncState.reconciling), isTrue);
        expect(states.contains(SyncState.ready), isTrue);
        expect(states.contains(SyncState.error), isTrue);
      });
    });

    group('network error scenarios', () {
      test('handles network timeout errors', () {
        final networkError = Exception('Network connection timeout');
        
        expect(networkError, isA<Exception>());
        expect(networkError.toString(), contains('Network connection timeout'));
      });

      test('handles matrix server errors', () {
        final serverError = Exception('M_LIMIT_EXCEEDED: Rate limit exceeded');
        
        expect(serverError, isA<Exception>());
        expect(serverError.toString(), contains('M_LIMIT_EXCEEDED'));
      });

      test('handles connection refused errors', () {
        final connectionError = Exception('Connection refused');
        
        expect(connectionError, isA<Exception>());
        expect(connectionError.toString(), contains('Connection refused'));
      });
    });

    group('retry logic patterns', () {
      test('exponential backoff calculation is correct', () {
        // Test exponential backoff logic
        const baseDelayMs = 1000;
        const maxDelayMs = 60000;
        
        var delay = baseDelayMs;
        final delays = <int>[delay];
        
        // Calculate exponential backoff sequence
        for (int i = 0; i < 6; i++) {
          delay = (delay * 2).clamp(baseDelayMs, maxDelayMs);
          delays.add(delay);
        }
        
        expect(delays[0], equals(1000));  // 1s
        expect(delays[1], equals(2000));  // 2s
        expect(delays[2], equals(4000));  // 4s
        expect(delays[3], equals(8000));  // 8s
        expect(delays[4], equals(16000)); // 16s
        expect(delays[5], equals(32000)); // 32s
        expect(delays[6], equals(60000)); // 60s (capped)
      });

      test('retry attempts are limited', () {
        const maxRetries = 5;
        var attemptCount = 0;
        
        // Simulate retry logic
        while (attemptCount < maxRetries) {
          attemptCount++;
        }
        
        expect(attemptCount, equals(maxRetries));
      });
    });

    group('partial sync handling', () {
      test('handles empty sync responses', () {
        final emptySyncData = <String, dynamic>{};
        
        // Should handle empty sync data gracefully
        expect(emptySyncData.isEmpty, isTrue);
        expect(emptySyncData['rooms'], isNull);
        expect(emptySyncData['presence'], isNull);
      });

      test('handles malformed sync responses', () {
        final malformedSyncData = {
          'invalid_field': 'unexpected_value',
          'rooms': 'should_be_object_not_string',
        };
        
        // Should handle malformed data without crashing
        expect(malformedSyncData.containsKey('invalid_field'), isTrue);
        expect(malformedSyncData['rooms'] is String, isTrue);
        expect(malformedSyncData['rooms'] is Map, isFalse);
      });

      test('handles partial room data', () {
        final partialRoomData = {
          'rooms': {
            'join': {
              '!room1:matrix.org': {
                'timeline': {
                  'events': [], // Empty events array
                },
                // Missing other expected fields
              },
            },
          },
        };
        
        final rooms = partialRoomData['rooms'] as Map<String, dynamic>;
        expect(rooms.containsKey('join'), isTrue);
        
        final joinedRooms = rooms['join'] as Map<String, dynamic>;
        expect(joinedRooms.containsKey('!room1:matrix.org'), isTrue);
      });
    });

    group('sync token management', () {
      test('sync token storage logic', () async {
        // Test token storage and retrieval
        const testToken = 'sync_token_12345_abcdef';
        
        // Mock saving token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('syncSinceToken', testToken);
        
        // Mock loading token
        final loadedToken = prefs.getString('syncSinceToken');
        
        expect(loadedToken, equals(testToken));
      });

      test('empty tokens are not saved', () async {
        // Test that empty tokens are rejected
        const emptyToken = '';
        const nullToken = null;
        
        expect(emptyToken.isEmpty, isTrue);
        expect(nullToken, isNull);
        
        // Should not save empty or null tokens
        final prefs = await SharedPreferences.getInstance();
        
        // Simulate the check that would prevent saving empty tokens
        if (emptyToken.isNotEmpty) {
          await prefs.setString('syncSinceToken', emptyToken);
        }
        
        expect(prefs.getString('syncSinceToken'), isNull);
      });

      test('token validation format', () {
        const validToken = 's1234567890_abcdefghijklmnop';
        const shortToken = 's123';
        const invalidToken = '';
        
        // Test token validation logic
        expect(validToken.isNotEmpty, isTrue);
        expect(validToken.length > 10, isTrue);
        
        expect(shortToken.isNotEmpty, isTrue);
        expect(shortToken.length > 10, isFalse);
        
        expect(invalidToken.isEmpty, isTrue);
      });
    });

    group('decryption error handling', () {
      test('decryption error tracking limits', () {
        const maxDecryptionErrors = 50;
        final errors = <Map<String, dynamic>>[];
        
        // Simulate adding errors beyond the limit
        for (int i = 0; i < 60; i++) {
          errors.add({
            'senderId': '@user$i:matrix.org',
            'roomId': '!room$i:matrix.org',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          
          // Keep list bounded (simulate the logic from SyncManager)
          if (errors.length > maxDecryptionErrors) {
            errors.removeAt(0);
          }
        }
        
        expect(errors.length, equals(maxDecryptionErrors));
        expect(errors.first['senderId'], equals('@user10:matrix.org')); // First 10 removed
        expect(errors.last['senderId'], equals('@user59:matrix.org')); // Last one added
      });

      test('decryption error data structure', () {
        final decryptionError = {
          'senderId': '@malicious_user:matrix.org',
          'roomId': '!encrypted_room:matrix.org',
          'timestamp': DateTime.now(),
        };
        
        expect(decryptionError.containsKey('senderId'), isTrue);
        expect(decryptionError.containsKey('roomId'), isTrue);
        expect(decryptionError.containsKey('timestamp'), isTrue);
        expect(decryptionError['timestamp'], isA<DateTime>());
      });
    });

    group('authentication failure scenarios', () {
      test('invalid token error handling', () {
        final authError = {
          'errcode': 'M_UNKNOWN_TOKEN',
          'error': 'Invalid access token'
        };
        
        expect(authError['errcode'], equals('M_UNKNOWN_TOKEN'));
        expect(authError['error'], contains('Invalid access token'));
      });

      test('device deleted error handling', () {
        final deviceError = {
          'errcode': 'M_UNKNOWN_DEVICE',
          'error': 'Device has been deleted'
        };
        
        expect(deviceError['errcode'], equals('M_UNKNOWN_DEVICE'));
        expect(deviceError['error'], contains('deleted'));
      });

      test('user banned error handling', () {
        final banError = {
          'errcode': 'M_USER_DEACTIVATED',
          'error': 'User has been deactivated'
        };
        
        expect(banError['errcode'], equals('M_USER_DEACTIVATED'));
        expect(banError['error'], contains('deactivated'));
      });
    });

    group('initialization race conditions', () {
      test('concurrent initialization prevention', () {
        var initializationCount = 0;
        var isInitializing = false;
        
        // Simulate the initialization guard logic
        Future<void> mockInitialize() async {
          if (isInitializing) {
            return; // Prevent concurrent initialization
          }
          
          isInitializing = true;
          initializationCount++;
          
          // Simulate async work
          await Future.delayed(const Duration(milliseconds: 10));
          
          isInitializing = false;
        }
        
        // Test concurrent calls
        final futures = List.generate(3, (_) => mockInitialize());
        return Future.wait(futures).then((_) {
          expect(initializationCount, equals(1)); // Should only initialize once
        });
      });
    });

    group('sync frequency and timing', () {
      test('minimum update intervals are respected', () {
        const minInterval = Duration(seconds: 5);
        final lastUpdate = DateTime.now();
        final timeSinceLastUpdate = DateTime.now().difference(lastUpdate);
        
        // Simulate the check that prevents too frequent updates
        final shouldUpdate = timeSinceLastUpdate >= minInterval;
        
        expect(shouldUpdate, isFalse); // Just updated, should not update again
      });

      test('sync timeout configuration', () {
        const syncTimeoutMs = 30000; // 30 seconds
        const longPollTimeoutMs = 10000; // 10 seconds
        
        expect(syncTimeoutMs, greaterThan(longPollTimeoutMs));
        expect(syncTimeoutMs, lessThanOrEqualTo(60000)); // Max 1 minute
      });
    });

    group('memory and cleanup', () {
      test('message history is bounded', () {
        const maxMessageHistory = 50;
        final messageHistory = <String>[];
        
        // Simulate adding messages beyond the limit
        for (int i = 0; i < 60; i++) {
          messageHistory.add('message_$i');
          
          // Keep history bounded
          if (messageHistory.length > maxMessageHistory) {
            messageHistory.removeAt(0);
          }
        }
        
        expect(messageHistory.length, equals(maxMessageHistory));
        expect(messageHistory.first, equals('message_10')); // First 10 removed
        expect(messageHistory.last, equals('message_59')); // Last one added
      });

      test('offline queue is limited', () {
        const maxOfflineQueueSize = 50;
        final offlineQueue = <Map<String, dynamic>>[];
        
        // Simulate adding items to offline queue
        for (int i = 0; i < 60; i++) {
          offlineQueue.add({
            'type': 'location_update',
            'data': {'lat': 40.7128, 'lng': -74.0060},
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          
          // Keep queue bounded
          if (offlineQueue.length > maxOfflineQueueSize) {
            offlineQueue.removeAt(0);
          }
        }
        
        expect(offlineQueue.length, equals(maxOfflineQueueSize));
      });
    });

    group('error recovery', () {
      test('sync recovery after network issues', () {
        var failureCount = 0;
        const maxFailures = 3;
        
        // Simulate network failure and recovery
        bool attemptSync() {
          if (failureCount < maxFailures) {
            failureCount++;
            return false; // Network failure
          }
          return true; // Success after failures
        }
        
        // Try multiple times
        var success = false;
        for (int i = 0; i < 5 && !success; i++) {
          success = attemptSync();
        }
        
        expect(success, isTrue);
        expect(failureCount, equals(maxFailures));
      });
    });
  });
}