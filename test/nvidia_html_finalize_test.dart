import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/nvidia_service.dart';

void main() {
  const base = '''
<!DOCTYPE html><html><head><meta charset="UTF-8"><style>.page{padding:1px}</style></head>
<body><div class="page"><h2>Summary</h2><p>old</p><h2>Experience</h2><p>old job</p></div></body></html>
''';

  test('isCompleteResumeHtml rejects style-only junk', () {
    const styleOnly = '<style>body{color:red}</style>\n';
    expect(NvidiaService.isCompleteResumeHtml(styleOnly), isFalse);
  });

  test('finalizeHtml throws on truncated style-only output', () {
    const style = '<style>.page{}</style>';
    expect(
      () => NvidiaService.finalizeHtml(style, base),
      throwsA(isA<Exception>()),
    );
  });

  test('finalizeHtml merges page fragment into base keeping style', () {
    final page = '<div class="page"><h2>Summary</h2><p>${'tailored ' * 80}</p>'
        '<h2>Experience</h2><p>${'job ' * 80}</p></div>';
    final out = NvidiaService.finalizeHtml(page, base);
    expect(out.contains('<style>.page{padding:1px}</style>'), isTrue);
    expect(out.contains('tailored'), isTrue);
    expect(out.contains('old job'), isFalse);
    expect(out.contains('</html>'), isTrue);
  });

  test('restoreStyle injects CSS into head without wiping body', () {
    const style = '<style>.page{padding:1px}</style>';
    const html =
        '<!DOCTYPE html><html><head><meta charset="UTF-8"></head><body><div class="page"><h2>Summary</h2><p>x</p></div></body></html>';
    final out = NvidiaService.restoreStyle(html, style);
    expect(out.contains(style), isTrue);
    expect(out.contains('Summary'), isTrue);
  });
}
