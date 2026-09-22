import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/gemini_service.dart';

const _base = '''
<!DOCTYPE html><html><head><style>.page{}</style></head>
<body><div class="page"><h2>Summary</h2><p>old summary text here for length padding xx</p>
<h2>Experience</h2><p>old experience text here for length padding xx</p>
<h2>Skills</h2><p>Dart</p></div></body></html>
''';

String _page(String summary, String experience) =>
    '<div class="page"><h2>Summary</h2><p>$summary</p>'
    '<h2>Experience</h2><p>$experience</p>'
    '<h2>Skills</h2><p>Dart Flutter</p></div>';

void main() {
  test('tailorResume strips markdown fences and merges into base', () async {
    final page = _page('${'tailored summary ' * 40}', '${'tailored job ' * 40}');
    final result = await GeminiService.tailorResume(
      'some JD',
      apiKey: 'test-key',
      baseHtmlOverride: _base,
      generateOverride: (prompt) async {
        expect(prompt, contains('Summary'));
        return '```html\n$page\n```';
      },
    );

    expect(result, contains('<style>.page{}</style>'));
    expect(result, contains('tailored summary'));
  });

  test('tailorResume keeps the base html and jd in the prompt', () async {
    final page = _page('${'ok summary ' * 40}', '${'ok experience ' * 40}');
    final result = await GeminiService.tailorResume(
      'Senior Flutter developer',
      apiKey: 'test-key',
      baseHtmlOverride: _base.replaceFirst('old summary', 'BASE_MARKER'),
      generateOverride: (prompt) async {
        expect(prompt, contains('BASE_MARKER'));
        expect(prompt, contains('Senior Flutter developer'));
        return page;
      },
    );

    expect(result, contains('ok summary'));
  });

  test('tailorResume requires apiKey', () async {
    expect(
      () => GeminiService.tailorResume(
        'some JD',
        apiKey: '   ',
        baseHtmlOverride: _base,
        generateOverride: (prompt) async => _page('a' * 200, 'b' * 200),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
