import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/screens/onboarding/welcome_screen.dart';

void main() {
  group('WelcomeScreen Widget Tests', () {
    Widget buildTestWidget({Map<String, WidgetBuilder>? routes}) {
      return MaterialApp(
        home: WelcomeScreen(),
        routes: routes ?? {},
      );
    }

    Future<void> pumpWelcomeScreen(WidgetTester tester, {Map<String, WidgetBuilder>? routes}) async {
      await tester.pumpWidget(buildTestWidget(routes: routes));
      // Advance past the Future.delayed timers (300ms, 600ms, 1000ms)
      await tester.pump(const Duration(milliseconds: 1100));
    }

    testWidgets('should display all essential UI elements', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester, routes: {
        '/server_select': (context) => const Scaffold(body: Text('Server Select')),
        '/login': (context) => const Scaffold(body: Text('Login')),
      });

      expect(find.text('WELCOME TO'), findsOneWidget);
      expect(find.text('Grid'), findsOneWidget);
      expect(find.text('Connect with friends and share your location\nsecurely in real-time'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Custom Provider'), findsOneWidget);
    });

    testWidgets('should display logo image', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester);
      expect(find.byType(Image), findsAtLeastNWidgets(1));
    });

    testWidgets('should display avatar network with circular avatars', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets('should display terms and privacy text with links', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester);

      expect(find.textContaining('By continuing, you agree to our'), findsOneWidget);
      expect(find.textContaining('Privacy Policy'), findsOneWidget);
      expect(find.textContaining('Terms of Service'), findsOneWidget);
    });

    testWidgets('Get Started button should navigate to server select', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester, routes: {
        '/server_select': (context) => const Scaffold(body: Text('Server Select Screen')),
      });

      await tester.ensureVisible(find.text('Get Started'));
      await tester.pump();
      await tester.tap(find.text('Get Started'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Server Select Screen'), findsOneWidget);
    });

    testWidgets('Custom Provider button should navigate to login', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester, routes: {
        '/login': (context) => const Scaffold(body: Text('Login Screen')),
      });

      await tester.ensureVisible(find.text('Custom Provider'));
      await tester.pump();
      await tester.tap(find.text('Custom Provider'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Login Screen'), findsOneWidget);
    });

    testWidgets('should have proper button styling and icons', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester);

      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNWidgets(2));
    });

    testWidgets('should display proper welcome badge styling', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester);

      expect(find.text('WELCOME TO'), findsOneWidget);
      final welcomeBadge = find.ancestor(
        of: find.text('WELCOME TO'),
        matching: find.byType(Container),
      );
      expect(welcomeBadge, findsAtLeastNWidgets(1));
    });
  });
}
