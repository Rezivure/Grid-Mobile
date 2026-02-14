import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/utilities/time_ago_formatter.dart';

void main() {
  group('TimeAgoFormatter.format', () {
    test('null returns Off Grid', () {
      expect(TimeAgoFormatter.format(null), 'Off Grid');
    });

    test('Offline string returns Off Grid', () {
      expect(TimeAgoFormatter.format('Offline'), 'Off Grid');
    });

    test('just now (< 30 seconds)', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 10)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), 'Just now');
    });

    test('seconds ago (30-59s)', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 45)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), contains('s ago'));
    });

    test('minutes ago', () {
      final ts = DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), '5m ago');
    });

    test('hours ago', () {
      final ts = DateTime.now().subtract(const Duration(hours: 3)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), '3h ago');
    });

    test('days ago (< 7)', () {
      final ts = DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), '3d ago');
    });

    test('7+ days returns Off Grid', () {
      final ts = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), 'Off Grid');
    });

    test('future timestamp returns Off Grid', () {
      final ts = DateTime.now().add(const Duration(hours: 1)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), 'Off Grid');
    });

    test('invalid string returns Off Grid', () {
      expect(TimeAgoFormatter.format('not-a-date'), 'Off Grid');
    });

    test('empty string returns Off Grid', () {
      expect(TimeAgoFormatter.format(''), 'Off Grid');
    });

    test('1 minute ago', () {
      final ts = DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), '1m ago');
    });

    test('23 hours ago', () {
      final ts = DateTime.now().subtract(const Duration(hours: 23)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), '23h ago');
    });

    test('1 day ago', () {
      final ts = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), '1d ago');
    });

    test('6 days ago', () {
      final ts = DateTime.now().subtract(const Duration(days: 6)).toIso8601String();
      expect(TimeAgoFormatter.format(ts), '6d ago');
    });
  });

  group('TimeAgoFormatter.getStatusColor', () {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.blue);

    test('Off Grid returns dimmed color', () {
      final color = TimeAgoFormatter.getStatusColor('Off Grid', colorScheme);
      expect(color.opacity, lessThan(1.0));
    });

    test('Invitation Sent returns dimmed color', () {
      final color = TimeAgoFormatter.getStatusColor('Invitation Sent', colorScheme);
      expect(color.opacity, lessThan(1.0));
    });

    test('Just now returns primary', () {
      final color = TimeAgoFormatter.getStatusColor('Just now', colorScheme);
      expect(color, colorScheme.primary);
    });

    test('minutes ago returns primary', () {
      final color = TimeAgoFormatter.getStatusColor('5m ago', colorScheme);
      expect(color, colorScheme.primary);
    });

    test('seconds ago returns primary', () {
      final color = TimeAgoFormatter.getStatusColor('30s ago', colorScheme);
      expect(color, colorScheme.primary);
    });

    test('hours ago returns yellow', () {
      final color = TimeAgoFormatter.getStatusColor('3h ago', colorScheme);
      expect(color, Colors.yellow);
    });

    test('days ago returns red', () {
      final color = TimeAgoFormatter.getStatusColor('2d ago', colorScheme);
      expect(color, Colors.red);
    });
  });
}
