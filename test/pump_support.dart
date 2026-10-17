import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxRounds = 400,
}) async {
  for (var i = 0; i < maxRounds && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpRounds(WidgetTester tester, int rounds) =>
    pumpUntil(tester, () => false, maxRounds: rounds);

bool cropReady(WidgetTester tester) {
  final button = find.widgetWithText(FilledButton, 'Use crop');
  return button.evaluate().isNotEmpty &&
      tester.widget<FilledButton>(button).onPressed != null;
}
