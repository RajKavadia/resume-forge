import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/gemini_service.dart';

void main() {
  test('tailorResume strips markdown fences', () async {
    final result = await GeminiService.tailorResume(
      'some JD',
      apiKey: 'test-key',
      baseHtmlOverride: '<!DOCTYPE html><html></html>',
      generateOverride: (prompt) async {
        expect(prompt, contains('<!DOCTYPE html>'));
        return '```html\n<!DOCTYPE html><html><body>OK</body></html>\n```';
      },
    );

    expect(result, equals('<!DOCTYPE html><html><body>OK</body></html>'));
  });

  test('tailorResume keeps the base html and jd in the prompt', () async {
    final result = await GeminiService.tailorResume(
      'Senior Flutter developer',
      apiKey: 'test-key',
      baseHtmlOverride: '<!DOCTYPE html><html><body>BASE</body></html>',
      generateOverride: (prompt) async {
        expect(prompt, contains('BASE'));
        expect(prompt, contains('Senior Flutter developer'));
        return '<!DOCTYPE html><html><body>OK</body></html>';
      },
    );

    expect(result, equals('<!DOCTYPE html><html><body>OK</body></html>'));
  });

  test('tailorResume requires apiKey', () async {
    expect(
      () => GeminiService.tailorResume(
        'some JD',
        apiKey: '   ',
        baseHtmlOverride: '<!DOCTYPE html><html></html>',
        generateOverride: (prompt) async => '<!DOCTYPE html><html></html>',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
