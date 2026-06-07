import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:resumetailor/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<String> mockTailorResume(
    String jobDescription, {
    required String apiKey,
  }) async {
    return '<!DOCTYPE html><html><body><h1>MOCK</h1><p>${jobDescription.length}</p></body></html>';
  }

  Future<void> mockSaveJournal(String html, String jobDescription) async {}

  testWidgets('smoke: shows validation messages', (tester) async {
    await tester.pumpWidget(const ResumeTailorApp());

    await tester.tap(find.text('Tailor My Resume'));
    await tester.pump();
    expect(find.text('Please enter your Gemini API key.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'test-key');
    await tester.tap(find.text('Tailor My Resume'));
    await tester.pump();
    expect(find.text('Please paste a Job Description first.'), findsOneWidget);
  });

  testWidgets('smoke: uses mock Gemini and navigates to preview', (tester) async {
    await tester.pumpWidget(
      ResumeTailorApp(
        tailorResume: mockTailorResume,
        saveJournal: mockSaveJournal,
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'test-key');
    await tester.enterText(find.byType(TextField).at(1), 'My JD text');

    await tester.tap(find.text('Tailor My Resume'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Tailored Resume'), findsOneWidget);
    expect(find.textContaining('Print'), findsOneWidget);
  });
}
