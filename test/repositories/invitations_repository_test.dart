import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/repositories/invitations_repository.dart';

void main() {
  late InvitationsRepository repository;

  setUp(() async {
    // Initialize SharedPreferences with mock values for testing
    SharedPreferences.setMockInitialValues({});
    repository = InvitationsRepository();
  });

  group('InvitationsRepository', () {
    test('saveInvitations stores JSON in SharedPreferences', () async {
      // Arrange
      final invitations = [
        {
          'id': 'inv1',
          'roomId': 'room1',
          'inviterId': 'user1',
          'inviteeId': 'user2',
          'status': 'pending',
          'timestamp': '2024-01-01T00:00:00.000Z',
        },
        {
          'id': 'inv2',
          'roomId': 'room2',
          'inviterId': 'user2',
          'inviteeId': 'user3',
          'status': 'accepted',
          'timestamp': '2024-01-02T00:00:00.000Z',
        }
      ];

      // Act
      await repository.saveInvitations(invitations);

      // Assert
      final prefs = await SharedPreferences.getInstance();
      final storedJson = prefs.getString('persisted_invitations');
      expect(storedJson, isNotNull);
      expect(storedJson, contains('inv1'));
      expect(storedJson, contains('room1'));
      expect(storedJson, contains('pending'));
    });

    test('loadInvitations returns parsed list', () async {
      // Arrange
      final invitations = [
        {
          'id': 'inv1',
          'roomId': 'room1',
          'inviterId': 'user1',
          'inviteeId': 'user2',
          'status': 'pending',
          'timestamp': '2024-01-01T00:00:00.000Z',
        }
      ];

      // First save some invitations
      await repository.saveInvitations(invitations);

      // Act
      final result = await repository.loadInvitations();

      // Assert
      expect(result, hasLength(1));
      expect(result[0]['id'], equals('inv1'));
      expect(result[0]['roomId'], equals('room1'));
      expect(result[0]['status'], equals('pending'));
    });

    test('loadInvitations empty returns []', () async {
      // Arrange - start with empty SharedPreferences (already set in setUp)

      // Act
      final result = await repository.loadInvitations();

      // Assert
      expect(result, isEmpty);
      expect(result, isA<List<Map<String, dynamic>>>());
    });

    test('clearInvitations removes key', () async {
      // Arrange
      final invitations = [
        {
          'id': 'inv1',
          'roomId': 'room1',
          'status': 'pending',
        }
      ];

      // First save some invitations
      await repository.saveInvitations(invitations);
      
      // Verify they were saved
      final beforeClear = await repository.loadInvitations();
      expect(beforeClear, hasLength(1));

      // Act
      await repository.clearInvitations();

      // Assert
      final prefs = await SharedPreferences.getInstance();
      final storedJson = prefs.getString('persisted_invitations');
      expect(storedJson, isNull);
      
      // Also verify that loadInvitations now returns empty
      final afterClear = await repository.loadInvitations();
      expect(afterClear, isEmpty);
    });

    test('round-trip: save then load returns same data', () async {
      // Arrange
      final originalInvitations = [
        {
          'id': 'inv1',
          'roomId': 'room1',
          'inviterId': 'user1',
          'inviteeId': 'user2',
          'status': 'pending',
          'timestamp': '2024-01-01T00:00:00.000Z',
          'metadata': {
            'roomName': 'Test Room',
            'inviterName': 'John Doe',
          }
        },
        {
          'id': 'inv2',
          'roomId': 'room2',
          'inviterId': 'user3',
          'inviteeId': 'user4',
          'status': 'accepted',
          'timestamp': '2024-01-02T00:00:00.000Z',
          'metadata': {
            'roomName': 'Another Room',
            'inviterName': 'Jane Smith',
          }
        }
      ];

      // Act
      await repository.saveInvitations(originalInvitations);
      final loadedInvitations = await repository.loadInvitations();

      // Assert
      expect(loadedInvitations, hasLength(originalInvitations.length));
      
      // Check first invitation
      expect(loadedInvitations[0]['id'], equals(originalInvitations[0]['id']));
      expect(loadedInvitations[0]['roomId'], equals(originalInvitations[0]['roomId']));
      expect(loadedInvitations[0]['status'], equals(originalInvitations[0]['status']));
      expect(loadedInvitations[0]['metadata'], equals(originalInvitations[0]['metadata']));
      
      // Check second invitation
      expect(loadedInvitations[1]['id'], equals(originalInvitations[1]['id']));
      expect(loadedInvitations[1]['roomId'], equals(originalInvitations[1]['roomId']));
      expect(loadedInvitations[1]['status'], equals(originalInvitations[1]['status']));
      expect(loadedInvitations[1]['metadata'], equals(originalInvitations[1]['metadata']));
    });

    test('saveInvitations overwrites existing data', () async {
      // Arrange
      final firstInvitations = [
        {
          'id': 'inv1',
          'status': 'pending',
        }
      ];
      
      final secondInvitations = [
        {
          'id': 'inv2',
          'status': 'accepted',
        },
        {
          'id': 'inv3',
          'status': 'declined',
        }
      ];

      // Act
      await repository.saveInvitations(firstInvitations);
      final afterFirst = await repository.loadInvitations();
      expect(afterFirst, hasLength(1));
      
      await repository.saveInvitations(secondInvitations);
      final afterSecond = await repository.loadInvitations();

      // Assert
      expect(afterSecond, hasLength(2));
      expect(afterSecond[0]['id'], equals('inv2'));
      expect(afterSecond[1]['id'], equals('inv3'));
      // The first invitation should be completely replaced
      expect(afterSecond.any((inv) => inv['id'] == 'inv1'), isFalse);
    });

    test('handles empty invitations list', () async {
      // Arrange
      final emptyInvitations = <Map<String, dynamic>>[];

      // Act
      await repository.saveInvitations(emptyInvitations);
      final result = await repository.loadInvitations();

      // Assert
      expect(result, isEmpty);
    });

    test('handles complex nested data structures', () async {
      // Arrange
      final complexInvitations = [
        {
          'id': 'complex1',
          'nested': {
            'level1': {
              'level2': ['item1', 'item2'],
              'number': 42,
              'boolean': true,
            }
          },
          'list': [1, 2, 3],
          'mixedList': ['string', 123, true, null],
        }
      ];

      // Act
      await repository.saveInvitations(complexInvitations);
      final result = await repository.loadInvitations();

      // Assert
      expect(result, hasLength(1));
      expect(result[0]['id'], equals('complex1'));
      expect(result[0]['nested']['level1']['level2'], equals(['item1', 'item2']));
      expect(result[0]['nested']['level1']['number'], equals(42));
      expect(result[0]['nested']['level1']['boolean'], equals(true));
      expect(result[0]['list'], equals([1, 2, 3]));
      expect(result[0]['mixedList'], equals(['string', 123, true, null]));
    });
  });
}