import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/nvidia_service.dart';

void main() {
  test('NvidiaService has correct endpoint and default model', () {
    expect(
      NvidiaService.endpoint,
      equals('https://integrate.api.nvidia.com/v1/chat/completions'),
    );
    expect(
      NvidiaService.defaultModel,
      equals('nvidia/nemotron-3-ultra-550b-a55b'),
    );
  });

  test('tailorResume strips markdown fences', () async {
    final result = await NvidiaService.tailorResume(
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

  test('tailorResume requires apiKey', () async {
    expect(
      () => NvidiaService.tailorResume(
        'some JD',
        apiKey: '   ',
        baseHtmlOverride: '<!DOCTYPE html><html></html>',
        generateOverride: (prompt) async => '<!DOCTYPE html><html></html>',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
