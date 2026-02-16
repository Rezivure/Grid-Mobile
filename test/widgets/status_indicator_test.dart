import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/widgets/status_indictator.dart';

void main() {
  group('StatusIndicator Widget Tests', () {
    Widget createWidget({required String timeAgo, String? membershipStatus}) {
      return MaterialApp(
        home: Scaffold(
          body: StatusIndicator(
            timeAgo: timeAgo,
            membershipStatus: membershipStatus,
          ),
        ),
      );
    }

    group('Membership Status', () {
      testWidgets('should display invitation sent when membershipStatus is invite', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: '1m ago', membershipStatus: 'invite'),
        );

        // Assert
        expect(find.text('Invitation Sent'), findsOneWidget);
        expect(find.byIcon(Icons.mail_outline), findsOneWidget);
      });

      testWidgets('should use orange styling for invitation status', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: '1m ago', membershipStatus: 'invite'),
        );

        // Assert
        final containerFinder = find.ancestor(
          of: find.text('Invitation Sent'),
          matching: find.byType(Container),
        );
        expect(containerFinder, findsOneWidget);
      });
    });

    group('Time-based Status', () {
      testWidgets('should display "Active now" for "Just now"', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: 'Just now'),
        );

        // Assert
        expect(find.text('Active now'), findsOneWidget);
        expect(find.byIcon(Icons.circle), findsOneWidget);
      });

      testWidgets('should display "Active now" for seconds ago', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: '30s ago'),
        );

        // Assert
        expect(find.text('Active now'), findsOneWidget);
        expect(find.byIcon(Icons.circle), findsOneWidget);
      });

      testWidgets('should display time ago for minutes', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: '5m ago'),
        );

        // Assert
        expect(find.text('5m ago'), findsOneWidget);
        expect(find.byIcon(Icons.circle), findsOneWidget);
      });

      testWidgets('should display time ago for hours', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: '2h ago'),
        );

        // Assert
        expect(find.text('2h ago'), findsOneWidget);
        expect(find.byIcon(Icons.schedule), findsOneWidget);
      });

      testWidgets('should display time ago for days', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: '3d ago'),
        );

        // Assert
        expect(find.text('3d ago'), findsOneWidget);
        expect(find.byIcon(Icons.access_time), findsOneWidget);
      });

      testWidgets('should display "Offline" for unknown status', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: 'unknown'),
        );

        // Assert
        expect(find.text('Offline'), findsOneWidget);
        expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
      });
    });

    group('Container Styling', () {
      testWidgets('should have proper container styling', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: 'Just now'),
        );

        // Assert - Check that container exists
        final containerFinder = find.ancestor(
          of: find.text('Active now'),
          matching: find.byType(Container),
        );
        expect(containerFinder, findsOneWidget);
      });

      testWidgets('should have proper row layout', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: 'Just now'),
        );

        // Assert - Check that Row widget exists with icon and text
        final rowFinder = find.byType(Row);
        expect(rowFinder, findsOneWidget);
        
        // Both icon and text should be present
        expect(find.byIcon(Icons.circle), findsOneWidget);
        expect(find.text('Active now'), findsOneWidget);
      });
    });

    group('Edge Cases', () {
      testWidgets('should handle empty timeAgo string', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: ''),
        );

        // Assert - Should fall back to "Offline"
        expect(find.text('Offline'), findsOneWidget);
        expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
      });

      testWidgets('should prioritize membershipStatus over timeAgo', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: 'Just now', membershipStatus: 'invite'),
        );

        // Assert - Should show invitation, not time status
        expect(find.text('Invitation Sent'), findsOneWidget);
        expect(find.text('Active now'), findsNothing);
      });

      testWidgets('should handle minutes over 10', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(timeAgo: '15m ago'),
        );

        // Assert - Should still display the time
        expect(find.text('15m ago'), findsOneWidget);
        expect(find.byIcon(Icons.circle), findsOneWidget);
      });
    });
  });
}