import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/models/pending_message.dart';

void main() {
  group('PendingMessage', () {
    final mockEventJson = {
      'type': 'm.room.message',
      'content': {
        'msgtype': 'm.text',
        'body': 'Test message',
      },
      'event_id': '\$event123',
      'sender': '@user:matrix.org',
      'origin_server_ts': 1677649200000,
    };

    test('constructor with all fields', () {
      final event = MatrixEvent.fromJson(mockEventJson);
      final queuedTime = DateTime(2023, 3, 1, 12, 0, 0);
      
      final pendingMessage = PendingMessage(
        roomId: '!room:matrix.org',
        eventId: 'temp-123',
        event: event,
        queuedAt: queuedTime,
      );

      expect(pendingMessage.roomId, '!room:matrix.org');
      expect(pendingMessage.eventId, 'temp-123');
      expect(pendingMessage.event.type, 'm.room.message');
      expect(pendingMessage.queuedAt, queuedTime);
    });

    test('constructor with default queuedAt (current time)', () {
      final event = MatrixEvent.fromJson(mockEventJson);
      final before = DateTime.now();
      
      final pendingMessage = PendingMessage(
        roomId: '!room:matrix.org',
        eventId: 'temp-456',
        event: event,
      );
      
      final after = DateTime.now();

      expect(pendingMessage.queuedAt.isAfter(before) || pendingMessage.queuedAt.isAtSameMomentAs(before), true);
      expect(pendingMessage.queuedAt.isBefore(after) || pendingMessage.queuedAt.isAtSameMomentAs(after), true);
    });

    test('toJson serializes correctly', () {
      final event = MatrixEvent.fromJson(mockEventJson);
      final queuedTime = DateTime(2023, 3, 1, 12, 0, 0);
      
      final pendingMessage = PendingMessage(
        roomId: '!room:matrix.org',
        eventId: 'temp-789',
        event: event,
        queuedAt: queuedTime,
      );

      final json = pendingMessage.toJson();

      expect(json['roomId'], '!room:matrix.org');
      expect(json['eventId'], 'temp-789');
      expect(json['event'], isA<Map<String, dynamic>>());
      expect(json['queuedAt'], '2023-03-01T12:00:00.000');
    });

    test('fromJson deserializes correctly', () {
      final queuedTime = DateTime(2023, 3, 1, 12, 0, 0);
      final json = {
        'roomId': '!room:matrix.org',
        'eventId': 'temp-101112',
        'event': mockEventJson,
        'queuedAt': queuedTime.toIso8601String(),
      };

      final pendingMessage = PendingMessage.fromJson(json);

      expect(pendingMessage.roomId, '!room:matrix.org');
      expect(pendingMessage.eventId, 'temp-101112');
      expect(pendingMessage.event.type, 'm.room.message');
      expect(pendingMessage.queuedAt, queuedTime);
    });

    test('JSON roundtrip preserves all data', () {
      final event = MatrixEvent.fromJson(mockEventJson);
      final queuedTime = DateTime(2023, 3, 1, 12, 0, 0);
      
      final original = PendingMessage(
        roomId: '!roundtrip:matrix.org',
        eventId: 'temp-roundtrip',
        event: event,
        queuedAt: queuedTime,
      );

      final json = original.toJson();
      final restored = PendingMessage.fromJson(json);

      expect(restored.roomId, original.roomId);
      expect(restored.eventId, original.eventId);
      expect(restored.event.type, original.event.type);
      expect(restored.queuedAt, original.queuedAt);
    });

    test('toString includes key information', () {
      final event = MatrixEvent.fromJson(mockEventJson);
      final queuedTime = DateTime(2023, 3, 1, 12, 0, 0);
      
      final pendingMessage = PendingMessage(
        roomId: '!room:matrix.org',
        eventId: 'temp-string',
        event: event,
        queuedAt: queuedTime,
      );

      final str = pendingMessage.toString();
      expect(str, contains('!room:matrix.org'));
      expect(str, contains('temp-string'));
      expect(str, contains('2023-03-01'));
    });

    test('handles different event types', () {
      final locationEventJson = {
        'type': 'm.room.message',
        'content': {
          'msgtype': 'm.location',
          'body': 'Location',
          'geo_uri': 'geo:40.7128,-74.0060',
        },
        'event_id': '\$location123',
        'sender': '@user:matrix.org',
        'origin_server_ts': 1677649200000,
      };

      final event = MatrixEvent.fromJson(locationEventJson);
      final pendingMessage = PendingMessage(
        roomId: '!room:matrix.org',
        eventId: 'temp-location',
        event: event,
      );

      expect(pendingMessage.event.content['msgtype'], 'm.location');
      expect(pendingMessage.event.content['geo_uri'], 'geo:40.7128,-74.0060');
    });

    test('queuedAt with microseconds precision', () {
      final event = MatrixEvent.fromJson(mockEventJson);
      final queuedTime = DateTime(2023, 3, 1, 12, 0, 0, 123, 456);
      
      final pendingMessage = PendingMessage(
        roomId: '!room:matrix.org',
        eventId: 'temp-micro',
        event: event,
        queuedAt: queuedTime,
      );

      final json = pendingMessage.toJson();
      final restored = PendingMessage.fromJson(json);

      expect(restored.queuedAt.millisecond, queuedTime.millisecond);
      expect(restored.queuedAt.microsecond, queuedTime.microsecond);
    });
  });
}