import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen validates api key and JD', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    await tester.ensureVisible(find.text('Tailor My Resume'));
    await tester.tap(find.text('Tailor My Resume'));
    await tester.pump();
    expect(find.text('Please enter your NVIDIA API key.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'test-key');
    await tester.ensureVisible(find.text('Tailor My Resume'));
    await tester.tap(find.text('Tailor My Resume'));
    await tester.pump();
    expect(find.text('Please capture text first.'), findsOneWidget);
  });
}
