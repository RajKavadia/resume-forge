import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/nvidia_service.dart';

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
  test('NvidiaService has correct endpoint and default model', () {
    expect(
      NvidiaService.endpoint,
      equals('https://integrate.api.nvidia.com/v1/chat/completions'),
    );
    expect(NvidiaService.defaultModel, equals('openai/gpt-oss-20b'));
  });

  test('tailorResume strips markdown fences and merges into base', () async {
    final page = _page('${'tailored summary ' * 40}', '${'tailored job ' * 40}');
    final result = await NvidiaService.tailorResume(
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
    expect(result, isNot(contains('old summary')));
  });

  test('tailorResume requires apiKey', () async {
    expect(
      () => NvidiaService.tailorResume(
        'some JD',
        apiKey: '   ',
        baseHtmlOverride: _base,
        generateOverride: (prompt) async => _page('a' * 200, 'b' * 200),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('normalizeSectionHtml extracts matching h2 section', () {
    final raw = '<div class="page"><h2>Summary</h2><p>new</p>'
        '<h2>Skills</h2><p>x</p></div>';
    final out = NvidiaService.normalizeSectionHtml(raw, 'Summary');
    expect(out, startsWith('<h2>Summary</h2>'));
    expect(out, contains('new'));
    expect(out, isNot(contains('Skills')));
  });
}
