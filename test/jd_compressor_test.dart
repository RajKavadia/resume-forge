import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/jd_compressor.dart';

void main() {
  group('JdCompressor.parse / briefOrFallback', () {
    test('parses role, keywords, responsibilities, key points', () {
      const raw = '''
ROLE: Senior Flutter Developer
COMPANY: Acme FinTech
KEYWORDS: Flutter, Dart, CI/CD, Kotlin, Compose
RESPONSIBILITIES:
- Build mobile apps
- Own CI pipelines
- Mentor juniors
KEY POINTS:
- 5+ years experience
- FinTech domain
- Remote OK
''';
      final brief = JdCompressor.parse(raw);
      expect(brief.role, 'Senior Flutter Developer');
      expect(brief.company, 'Acme FinTech');
      expect(brief.keywords, containsAll(['Flutter', 'Dart', 'CI/CD']));
      expect(brief.responsibilities, hasLength(3));
      expect(brief.keyPoints.first, contains('5+ years'));
      final prompt = brief.toPromptBrief();
      expect(prompt, contains('KEYWORDS:'));
      expect(prompt, contains('RESPONSIBILITIES:'));
    });

    test('briefOrFallback uses model brief when rich', () {
      const model = '''
ROLE: Android Engineer
COMPANY: Unknown
KEYWORDS: Kotlin, Coroutines
RESPONSIBILITIES:
- Ship features
KEY POINTS:
- Mid-level
''';
      final out = JdCompressor.briefOrFallback(model, 'huge noisy dump ' * 200);
      expect(out, contains('Kotlin'));
      expect(out.length, lessThan(800));
      expect(out, isNot(contains('huge noisy dump')));
    });

    test('briefOrFallback falls back when model output is junk', () {
      final out = JdCompressor.briefOrFallback(
        'sorry I cannot help',
        'Flutter engineer needed for CI/CD and Kotlin',
      );
      expect(out, contains('Flutter'));
    });

    test('trimScreenDump caps length', () {
      final big = 'x' * (JdCompressor.maxScreenDumpChars + 500);
      final t = JdCompressor.trimScreenDump(big);
      expect(t.length, lessThan(big.length));
      expect(t, contains('truncated'));
    });

    test('shouldSkipCompress for small dumps', () {
      expect(JdCompressor.shouldSkipCompress('Flutter CI/CD Kotlin'), isTrue);
      final big = 'requirement ' * 2000;
      expect(JdCompressor.shouldSkipCompress(big), isFalse);
    });

    test('buildCompressPrompt asks for keywords and responsibilities', () {
      final p = JdCompressor.buildCompressPrompt('Need a Flutter dev');
      expect(p, contains('KEYWORDS:'));
      expect(p, contains('RESPONSIBILITIES:'));
      expect(p, contains('KEY POINTS:'));
      expect(p, contains('Need a Flutter dev'));
    });
  });
}
