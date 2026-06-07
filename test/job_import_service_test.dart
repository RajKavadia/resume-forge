import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/job_import_service.dart';

void main() {
  test('importFromUrl uses override and cleans result', () async {
    final output = await JobImportService.importFromUrl(
      'https://example.com/job',
      importOverride: (url) async {
        expect(url, 'https://example.com/job');
        return '  Hello  \n\nHello\nWorld   ';
      },
    );

    expect(output, equals('Hello\nWorld'));
  });

  test('cleanExtractedText collapses whitespace and removes duplicates', () {
    const input = '''
  Job Title

Responsibilities
    Build things
    Build things

Requirements
  Flutter
  Flutter
''';

    final output = JobImportService.cleanExtractedText(input);

    expect(
      output,
      equals('Job Title\nResponsibilities\nBuild things\nRequirements\nFlutter'),
    );
  });

  test('cleanExtractedText trims empty lines', () {
    const input = '\n\n  One\n\n  Two  \n\n';

    final output = JobImportService.cleanExtractedText(input);

    expect(output, equals('One\nTwo'));
  });
}
