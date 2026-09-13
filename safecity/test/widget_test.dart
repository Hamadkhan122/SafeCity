import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safecity/screens/splash_screen.dart';

void main() {
  testWidgets('Splash screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SplashScreen()),
    );

    expect(find.text('SAFECITY'), findsOneWidget);
    expect(find.text('Protect • Report • Respond'), findsOneWidget);
  });
}
