import 'package:flutter/material.dart';
import 'package:flutter_intl_phone_field/flutter_intl_phone_field.dart';
import 'package:flutter_test/flutter_test.dart';

class TestWidget extends StatelessWidget {
  const TestWidget({Key? key, required this.phoneNumber, this.countryCode})
      : super(key: key);

  final String phoneNumber;
  final String? countryCode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Test Intl Phone Field',
        home: Scaffold(
          appBar: AppBar(title: const Text("")),
          body: IntlPhoneField(
            initialValue: phoneNumber,
            initialCountryCode: countryCode,
          ),
        ));
  }
}

void main() {
  testWidgets('Test flutter_intl_phone_field setup with completeNumber',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TestWidget(
      phoneNumber: '+447891234467',
    ));

    final countryCodeFinder = find.text('+44');
    final numberFinder = find.text('7891234467');

    expect(countryCodeFinder, findsOneWidget);
    expect(numberFinder, findsOneWidget);
  });

  testWidgets(
      'Test flutter_intl_phone_field setup with Guernsey number: +441481960194',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TestWidget(
      phoneNumber: '+441481960194',
      countryCode: 'GG',
    ));

    final countryCodeFinder = find.text('+44 1481');
    final numberFinder = find.text('960194');

    expect(countryCodeFinder, findsOneWidget);
    expect(numberFinder, findsOneWidget);
  });

  testWidgets(
      'Test flutter_intl_phone_field setup with UK number: +447891244567',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TestWidget(
      phoneNumber: '+447891244567',
      countryCode: 'GB',
    ));

    final countryCodeFinder = find.text('+44');
    final numberFinder = find.text('7891244567');

    expect(countryCodeFinder, findsOneWidget);
    expect(numberFinder, findsOneWidget);
  });
}
