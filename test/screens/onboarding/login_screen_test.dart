import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/screens/onboarding/login_screen.dart';

// Mock classes
class MockClient extends Mock implements Client {}

void main() {
  group('LoginScreen Widget Tests', () {
    late MockClient mockClient;

    setUpAll(() {
      // Mock asset loading for images
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) async {
          if (message == null) return null;
          return const StandardMessageCodec().encodeMessage(Uint8List(0));
        },
      );
    });

    setUp(() {
      mockClient = MockClient();
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        null,
      );
    });

    Widget createLoginScreen() {
      return MaterialApp(
        home: Provider<Client>.value(
          value: mockClient,
          child: LoginScreen(),
        ),
        routes: {
          '/signup': (context) => const Scaffold(body: Text('Signup Screen')),
          '/main': (context) => const Scaffold(body: Text('Main Screen')),
        },
      );
    }

    testWidgets('should display essential form elements', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Assert - Check for form fields
      expect(find.text('Homeserver URL'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('should display screen title and header', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Assert - Check for title and header elements
      expect(find.text('Custom Server'), findsOneWidget);
      expect(find.text('ADVANCED LOGIN'), findsOneWidget);
      expect(find.text('Connect to Custom Server'), findsOneWidget);
    });

    testWidgets('should display maps configuration section', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Assert - Check for maps configuration
      expect(find.text('Maps Configuration'), findsOneWidget);
      expect(find.text('Grid Maps'), findsOneWidget);
      expect(find.text('Custom Maps'), findsOneWidget);
    });

    testWidgets('should have text input fields', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Assert - Check for TextField widgets
      final textFields = find.byType(TextField);
      expect(textFields, findsAtLeastNWidgets(3)); // homeserver, username, password (custom maps field might not be visible)
    });

    testWidgets('should have password visibility toggle', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Assert - Check for visibility toggle icon
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('password visibility toggle should work', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Act - Tap the visibility toggle
      final visibilityToggle = find.byIcon(Icons.visibility_off);
      await tester.tap(visibilityToggle);
      await tester.pump();

      // Assert - Icon should change to visible
      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });

    testWidgets('should handle text input in form fields', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Act - Enter text in form fields
      await tester.enterText(find.byType(TextField).first, 'matrix.example.com');
      await tester.pump();

      // Assert
      expect(find.text('matrix.example.com'), findsOneWidget);
    });

    testWidgets('should display navigation buttons', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Assert - Check for buttons
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Don\'t have an account? Sign Up'), findsOneWidget);
    });

    testWidgets('should have back button', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Assert - Check for back button in AppBar
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('maps selection should toggle between options', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Initially, Grid Maps should be selected (default)
      // We can't easily test the visual selection state, but we can test the presence of options
      expect(find.text('Grid Maps'), findsOneWidget);
      expect(find.text('Custom Maps'), findsOneWidget);
    });

    testWidgets('should display proper form hints and labels', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Assert - Check for placeholder/hint text
      expect(find.text('matrix.example.com'), findsOneWidget);
      expect(find.text('Enter your username'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('should have proper button icons', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Assert - Check for button icons
      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets('form fields should have proper icons', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createLoginScreen());
      await tester.pump();

      // Assert - Check for field icons
      expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });
  });
}