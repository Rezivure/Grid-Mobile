import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/screens/settings/speed_units_screen.dart';
import 'package:grid_frontend/services/units_controller.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget buildTestWidget() {
    final theme = ThemeData.light(useMaterial3: true).copyWith(
      extensions: <ThemeExtension<dynamic>>[GridColors.light()],
    );
    return MaterialApp(theme: theme, home: const SpeedUnitsScreen());
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UnitsController.instance.load();
  });

  testWidgets('lists every unit with mph selected by default',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());

    expect(find.text('Miles per hour (mph)'), findsOneWidget);
    expect(find.text('Kilometers per hour (km/h)'), findsOneWidget);
    expect(find.text('Meters per second (m/s)'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('tapping a unit selects it (issue #361)',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());

    await tester.tap(find.text('Kilometers per hour (km/h)'));
    await tester.pumpAndSettle();

    expect(UnitsController.instance.speedUnit, SpeedUnit.kmh);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
