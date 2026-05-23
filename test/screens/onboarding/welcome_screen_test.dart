import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/screens/onboarding/welcome_screen.dart';
import 'package:grid_frontend/styles/grid_colors.dart';

void main() {
  group('WelcomeScreen Widget Tests', () {
    Widget buildTestWidget({Map<String, WidgetBuilder>? routes}) {
      final theme = ThemeData.light(useMaterial3: true).copyWith(
        extensions: <ThemeExtension<dynamic>>[GridColors.light()],
      );
      return MaterialApp(
        theme: theme,
        home: WelcomeScreen(),
        routes: routes ?? {},
      );
    }

    Future<void> pumpWelcomeScreen(WidgetTester tester, {Map<String, WidgetBuilder>? routes}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildTestWidget(routes: routes));
      await tester.pump(const Duration(milliseconds: 1100));
    }

    testWidgets('should display all essential UI elements', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester, routes: {
        '/server_select': (context) => const Scaffold(body: Text('Server Select')),
        '/login': (context) => const Scaffold(body: Text('Login')),
      });

      expect(find.text('Be hard to track.'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('I already have an account'), findsOneWidget);
      expect(find.text('Use a custom server'), findsOneWidget);
    });

    testWidgets('should display logo image', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester);
      expect(find.byType(Image), findsAtLeastNWidgets(1));
    });

    testWidgets('should display encryption badge', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester);
      expect(find.text('E2E ENCRYPTED · OPEN SOURCE'), findsOneWidget);
    });

    testWidgets('should display terms text', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester);

      expect(find.textContaining('By continuing you agree to our'), findsOneWidget);
      expect(find.textContaining('Terms & Privacy'), findsOneWidget);
    });

    testWidgets('Get started button should navigate to server select', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester, routes: {
        '/server_select': (context) => const Scaffold(body: Text('Server Select Screen')),
      });

      await tester.ensureVisible(find.text('Get started'));
      await tester.pump();
      await tester.tap(find.text('Get started'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Server Select Screen'), findsOneWidget);
    });

    testWidgets('custom server link should navigate to login', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester, routes: {
        '/login': (context) => const Scaffold(body: Text('Login Screen')),
      });

      await tester.ensureVisible(find.text('Use a custom server'));
      await tester.pump();
      await tester.tap(find.text('Use a custom server'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Login Screen'), findsOneWidget);
    });

    testWidgets('should have custom server link icon', (WidgetTester tester) async {
      await pumpWelcomeScreen(tester);

      expect(find.byIcon(Icons.link_rounded), findsOneWidget);
    });
  });
}
