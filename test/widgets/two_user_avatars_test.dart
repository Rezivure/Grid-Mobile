import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/widgets/two_user_avatars.dart';

void main() {
  group('TwoUserAvatars Widget Tests', () {
    Widget createWidget({required List<String> userIds}) {
      return MaterialApp(
        home: Scaffold(
          body: TwoUserAvatars(userIds: userIds),
        ),
      );
    }

    testWidgets('should display CircleAvatar container', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        createWidget(userIds: ['user1', 'user2']),
      );

      // Assert
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('should have correct radius', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        createWidget(userIds: ['user1', 'user2']),
      );

      // Assert - Check that CircleAvatar has radius 30
      final circleAvatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(circleAvatar.radius, equals(30));
    });

    testWidgets('should have Stack for positioning avatars', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        createWidget(userIds: ['user1', 'user2']),
      );

      // Assert - find the Stack that is a direct child of CircleAvatar
      expect(find.descendant(of: find.byType(CircleAvatar), matching: find.byType(Stack)), findsOneWidget);
    });

    testWidgets('should have two Positioned widgets', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        createWidget(userIds: ['user1', 'user2']),
      );

      // Assert - Two positioned widgets for the two avatars
      expect(find.byType(Positioned), findsNWidgets(2));
    });

    testWidgets('should handle single user by duplicating', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        createWidget(userIds: ['user1']),
      );

      // Assert - Should still have two positioned elements (duplicated user)
      expect(find.byType(Positioned), findsNWidgets(2));
      expect(find.descendant(of: find.byType(CircleAvatar), matching: find.byType(Stack)), findsOneWidget);
    });

    testWidgets('should handle empty user list gracefully', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        createWidget(userIds: []),
      );

      // Assert - Should still render without crashing
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.descendant(of: find.byType(CircleAvatar), matching: find.byType(Stack)), findsOneWidget);
    });

    testWidgets('should deduplicate identical userIds', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        createWidget(userIds: ['user1', 'user1', 'user1']),
      );

      // Assert - Should still render (duplicates the same user for 2nd position)
      expect(find.byType(Positioned), findsNWidgets(2));
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('should take only first two distinct users', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        createWidget(userIds: ['user1', 'user2', 'user3', 'user4']),
      );

      // Assert - Should only show two positioned avatars
      expect(find.byType(Positioned), findsNWidgets(2));
    });

    testWidgets('should handle very long userIds list', (WidgetTester tester) async {
      // Arrange
      final longUserList = List.generate(100, (index) => 'user$index');

      // Act
      await tester.pumpWidget(
        createWidget(userIds: longUserList),
      );

      // Assert - Should still only show two avatars
      expect(find.byType(Positioned), findsNWidgets(2));
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    group('Styling Tests', () {
      testWidgets('should have proper background color with opacity', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(userIds: ['user1', 'user2']),
        );

        // Assert - Test that the structure exists (can't easily test exact color)
        final circleAvatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
        expect(circleAvatar.backgroundColor, isNotNull);
      });

      testWidgets('should center content with proper alignment', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(userIds: ['user1', 'user2']),
        );

        // Assert - Check Stack alignment (use descendant to find the right Stack)
        final stackFinder = find.descendant(of: find.byType(CircleAvatar), matching: find.byType(Stack));
        final stack = tester.widget<Stack>(stackFinder);
        expect(stack.alignment, equals(Alignment.center));
      });
    });

    group('Edge Case Tests', () {
      testWidgets('should handle null or empty strings in userIds', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(userIds: ['', 'user2']),
        );

        // Assert - Should not crash
        expect(find.byType(CircleAvatar), findsOneWidget);
        expect(find.byType(Positioned), findsNWidgets(2));
      });

      testWidgets('should handle special characters in userIds', (WidgetTester tester) async {
        // Arrange & Act
        await tester.pumpWidget(
          createWidget(userIds: ['@user:matrix.org', '#room:server.com']),
        );

        // Assert - Should not crash
        expect(find.byType(CircleAvatar), findsOneWidget);
        expect(find.byType(Positioned), findsNWidgets(2));
      });
    });
  });
}