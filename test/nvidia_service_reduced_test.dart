import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/nvidia_service.dart';

const _base = '''
<!DOCTYPE html><html><head><style>body{font-size:13px}</style></head><body><div class="page">
<h1>Jane Doe</h1>
<h2>Summary</h2><p>SUMMARY_ORIGINAL</p>
<h2>Skills</h2><div><p>SKILLS_ORIGINAL</p></div>
<h2>Experience</h2><div class="entry"><ul><li>EXPERIENCE_ORIGINAL</li></ul></div>
<h2>Projects and Published Apps</h2><div class="entry"><p>PROJECTS_ORIGINAL</p></div>
<h2>Open Source Projects</h2><div class="oss-entry">OSS_ORIGINAL</div>
<h2>Education</h2><div class="edu-entry">EDUCATION_ORIGINAL</div>
</div></body></html>''';

void main() {
  test('reduced path merges tailored fragment back into full base HTML',
      () async {
    late String seenPrompt;
    final result = await NvidiaService.tailorResume(
      'Senior Flutter developer',
      apiKey: 'test-key',
      baseHtmlOverride: _base,
      sectionsToOptimize: const ['Summary'],
      generateOverride: (prompt) async {
        seenPrompt = prompt;
        // Model returns ONLY the tailored fragment for the reduced path.
        return '<h2>Summary</h2><p>SUMMARY_TAILORED with Kotlin</p>';
      },
    );

    // Prompt only carried the Summary section (smaller payload).
    expect(seenPrompt, contains('SUMMARY_ORIGINAL'));
    expect(seenPrompt, isNot(contains('EXPERIENCE_ORIGINAL')));

    // Result is the FULL document with only Summary replaced.
    expect(result, contains('<!DOCTYPE html>'));
    expect(result, contains('SUMMARY_TAILORED'));
    expect(result, isNot(contains('SUMMARY_ORIGINAL')));
    expect(result, contains('SKILLS_ORIGINAL'));
    expect(result, contains('EXPERIENCE_ORIGINAL'));
    expect(result, contains('PROJECTS_ORIGINAL'));
    expect(result, contains('OSS_ORIGINAL'));
    expect(result, contains('EDUCATION_ORIGINAL'));
    expect(result, contains('<style>body{font-size:13px}</style>'));
  });

  test('reduced path onDelta receives the fully-merged document', () async {
    final deltas = <String>[];
    final result = await NvidiaService.tailorResume(
      'JD',
      apiKey: 'test-key',
      baseHtmlOverride: _base,
      sectionsToOptimize: const ['Summary'],
      onDelta: deltas.add,
      generateOverride: (prompt) async =>
          '<h2>Summary</h2><p>SUMMARY_TAILORED</p>',
    );
    expect(deltas, isNotEmpty);
    // Final onDelta payload equals the merged, full document.
    expect(deltas.last, equals(result));
    expect(deltas.last, contains('EDUCATION_ORIGINAL'));
    expect(deltas.last, contains('SUMMARY_TAILORED'));
  });

  test('full path (empty sections) returns the model document unchanged',
      () async {
    final result = await NvidiaService.tailorResume(
      'JD',
      apiKey: 'test-key',
      baseHtmlOverride: _base,
      sectionsToOptimize: const [],
      generateOverride: (prompt) async {
        // Full path embeds the whole base HTML in the prompt.
        expect(prompt, contains('EXPERIENCE_ORIGINAL'));
        return '<!DOCTYPE html><html><body>FULL_OK</body></html>';
      },
    );
    expect(result, equals('<!DOCTYPE html><html><body>FULL_OK</body></html>'));
  });
}
