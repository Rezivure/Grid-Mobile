import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/screens/onboarding/welcome_screen.dart';

void main() {
  group('WelcomeScreen Widget Tests', () {
    // Set up asset mocking for tests
    setUpAll(() {
      // Mock asset loading for images
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) async {
          if (message == null) return null;
          // Return empty byte data for any asset
          return const StandardMessageCodec().encodeMessage(Uint8List(0));
        },
      );
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        null,
      );
    });

    testWidgets('should display all essential UI elements', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(),
          routes: {
            '/server_select': (context) => const Scaffold(body: Text('Server Select')),
            '/login': (context) => const Scaffold(body: Text('Login')),
          },
        ),
      );
      
      // Wait for initial render
      await tester.pump();
      
      // Assert - Check for main UI elements
      expect(find.text('WELCOME TO'), findsOneWidget);
      expect(find.text('Grid'), findsOneWidget);
      expect(find.text('Connect with friends and share your location\nsecurely in real-time'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Custom Provider'), findsOneWidget);
    });

    testWidgets('should display logo image', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(),
        ),
      );
      await tester.pump();
      
      // Assert - Check for logo image (even if assets don't load, Image widget should exist)
      expect(find.byType(Image), findsAtLeastNWidgets(1));
    });

    testWidgets('should display avatar network with circular avatars', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(),
        ),
      );
      await tester.pump();
      
      // Assert - Check for avatar-related widgets
      final customPaintFinder = find.byType(CustomPaint);
      expect(customPaintFinder, findsAtLeastNWidgets(1));
    });

    testWidgets('should display terms and privacy text with links', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(),
        ),
      );
      await tester.pump();
      
      // Assert - Check for legal text
      expect(find.textContaining('By continuing, you agree to our'), findsOneWidget);
      expect(find.textContaining('Privacy Policy'), findsOneWidget);
      expect(find.textContaining('Terms of Service'), findsOneWidget);
    });

    testWidgets('Get Started button should navigate to server select', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(),
          routes: {
            '/server_select': (context) => const Scaffold(body: Text('Server Select Screen')),
          },
        ),
      );
      await tester.pump();
      
      // Act
      final getStartedButton = find.text('Get Started');
      expect(getStartedButton, findsOneWidget);
      await tester.tap(getStartedButton);
      await tester.pump();
      
      // Assert
      expect(find.text('Server Select Screen'), findsOneWidget);
    });

    testWidgets('Custom Provider button should navigate to login', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('Login Screen')),
          },
        ),
      );
      await tester.pump();
      
      // Act
      final customProviderButton = find.text('Custom Provider');
      expect(customProviderButton, findsOneWidget);
      await tester.tap(customProviderButton);
      await tester.pump();
      
      // Assert
      expect(find.text('Login Screen'), findsOneWidget);
    });

    testWidgets('should have proper button styling and icons', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(),
        ),
      );
      await tester.pump();
      
      // Assert - Check for button icons
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      
      // Check for ElevatedButton widgets
      expect(find.byType(ElevatedButton), findsNWidgets(2));
    });

    testWidgets('should display proper welcome badge styling', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(),
        ),
      );
      await tester.pump();
      
      // Assert - Check for welcome badge container
      expect(find.text('WELCOME TO'), findsOneWidget);
      
      // The text should be within a Container with proper styling
      final welcomeBadge = find.ancestor(
        of: find.text('WELCOME TO'),
        matching: find.byType(Container),
      );
      expect(welcomeBadge, findsAtLeastNWidgets(1));
    });
  });
}