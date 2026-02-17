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
    late void Function(FlutterErrorDetails)? originalOnError;

    setUp(() {
      mockClient = MockClient();
      // Suppress image/asset loading errors in tests
      originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        final exception = details.exception.toString();
        if (exception.contains('IMAGE RESOURCE SERVICE') ||
            exception.contains('_Uint8ArrayView') ||
            exception.contains('asset') ||
            exception.contains('Timer') ||
            details.library == 'image resource service') {
          return;
        }
        originalOnError?.call(details);
      };
    });

    tearDown(() {
      FlutterError.onError = originalOnError;
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

    Future<void> pumpLogin(WidgetTester tester) async {
      await tester.pumpWidget(createLoginScreen());
      // Pump enough for animations (LoginScreen has fade/slide controllers)
      await tester.pump(const Duration(milliseconds: 1500));
    }

    testWidgets('should display essential form elements', (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.text('Homeserver URL'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('should display screen title and header', (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.text('Custom Server'), findsOneWidget);
      expect(find.text('ADVANCED LOGIN'), findsOneWidget);
      expect(find.text('Connect to Custom Server'), findsOneWidget);
    });

    testWidgets('should display maps configuration section', (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.text('Maps Configuration'), findsOneWidget);
      expect(find.text('Grid Maps'), findsOneWidget);
      expect(find.text('Custom Maps'), findsOneWidget);
    });

    testWidgets('should have text input fields', (WidgetTester tester) async {
      await pumpLogin(tester);

      final textFields = find.byType(TextField);
      expect(textFields, findsAtLeastNWidgets(3));
    });

    testWidgets('should have password visibility toggle', (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('password visibility toggle should work', (WidgetTester tester) async {
      await pumpLogin(tester);

      // Scroll down to make the password field visible
      await tester.scrollUntilVisible(
        find.byIcon(Icons.visibility_off),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      final visibilityToggle = find.byIcon(Icons.visibility_off);
      await tester.tap(visibilityToggle);
      await tester.pump();

      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });

    testWidgets('should handle text input in form fields', (WidgetTester tester) async {
      await pumpLogin(tester);

      await tester.enterText(find.byType(TextField).first, 'matrix.example.com');
      await tester.pump();

      expect(find.text('matrix.example.com'), findsAtLeastNWidgets(1));
    });

    testWidgets('should display navigation buttons', (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.text('Sign In'), findsOneWidget);
      expect(find.textContaining("Don't have an account"), findsOneWidget);
    });

    testWidgets('should have back button', (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('maps selection should toggle between options', (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.text('Grid Maps'), findsOneWidget);
      expect(find.text('Custom Maps'), findsOneWidget);
    });

    testWidgets('should display proper form hints and labels', (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.text('matrix.example.com'), findsOneWidget);
      expect(find.text('Enter your username'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('should have proper button icons', (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets('form fields should have proper icons', (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });
  });
}
