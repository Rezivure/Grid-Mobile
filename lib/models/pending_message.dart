import 'package:matrix/matrix.dart';

class PendingMessage {
  final String roomId;
  final String eventId;
  final MatrixEvent event;
  final DateTime queuedAt;

  PendingMessage({
    required this.roomId,
    required this.eventId,
    required this.event,
    DateTime? queuedAt,
  }) : queuedAt = queuedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'roomId': roomId,
      'eventId': eventId,
      'event': event.toJson(),
      'queuedAt': queuedAt.toIso8601String(),
    };
  }

  factory PendingMessage.fromJson(Map<String, dynamic> json) {
    return PendingMessage(
      roomId: json['roomId'] as String,
      eventId: json['eventId'] as String,
      event: MatrixEvent.fromJson(json['event'] as Map<String, dynamic>),
      queuedAt: DateTime.parse(json['queuedAt'] as String),
    );
  }

  @override
  String toString() {
    return 'PendingMessage{roomId: $roomId, eventId: $eventId, queuedAt: $queuedAt}';
  }
}