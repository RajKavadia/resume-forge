import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/gemini_service.dart';

const _base = '''
<!DOCTYPE html><html><head><style>body{font-size:13px}</style></head><body><div class="page">
<h1>Jane Doe</h1>
<h2>Summary</h2><p>SUMMARY_UNIQUE_BODY</p>
<h2>Skills</h2><div><p>SKILLS_UNIQUE_BODY</p></div>
<h2>Experience</h2><div class="entry"><ul><li>EXPERIENCE_UNIQUE_BODY</li></ul></div>
<h2>Projects and Published Apps</h2><div class="entry"><p>PROJECTS_UNIQUE_BODY</p></div>
<h2>Open Source Projects</h2><div class="oss-entry">OSS_UNIQUE_BODY</div>
<h2>Education</h2><div class="edu-entry">EDUCATION_UNIQUE_BODY</div>
</div></body></html>''';

void main() {
  const jd = 'Senior Flutter developer with Kotlin experience';

  test('empty sectionsToOptimize embeds the FULL base HTML (unchanged path)',
      () {
    final prompt = buildResumePrompt(_base, jd, const [], '');
    // Full document behavior preserved.
    expect(prompt, contains('BASE RESUME HTML:'));
    expect(prompt, contains('SUMMARY_UNIQUE_BODY'));
    expect(prompt, contains('SKILLS_UNIQUE_BODY'));
    expect(prompt, contains('EXPERIENCE_UNIQUE_BODY'));
    expect(prompt, contains('PROJECTS_UNIQUE_BODY'));
    expect(prompt, contains('OSS_UNIQUE_BODY'));
    expect(prompt, contains('EDUCATION_UNIQUE_BODY'));
    expect(prompt, contains(jd));
    // Full path asks for a complete HTML document.
    expect(prompt, contains('<!DOCTYPE html>'));
  });

  test('non-empty sectionsToOptimize embeds ONLY requested section fragments',
      () {
    final prompt = buildResumePrompt(_base, jd, const ['Summary'], '');
    // Requested section present.
    expect(prompt, contains('<h2>Summary</h2>'));
    expect(prompt, contains('SUMMARY_UNIQUE_BODY'));
    expect(prompt, contains(jd));
    // Non-selected sections' content must be ABSENT (smaller payload).
    expect(prompt, isNot(contains('SKILLS_UNIQUE_BODY')));
    expect(prompt, isNot(contains('EXPERIENCE_UNIQUE_BODY')));
    expect(prompt, isNot(contains('PROJECTS_UNIQUE_BODY')));
    expect(prompt, isNot(contains('OSS_UNIQUE_BODY')));
    expect(prompt, isNot(contains('EDUCATION_UNIQUE_BODY')));
    // Model is instructed to return only the fragments, not a whole document.
    expect(prompt, contains('RETURN ONLY THESE'));
  });

  test('reduced prompt is measurably smaller than the full-HTML prompt', () {
    final full = buildResumePrompt(_base, jd, const [], '');
    final reduced = buildResumePrompt(_base, jd, const ['Summary'], '');
    expect(reduced.length, lessThan(full.length));
  });

  test('UI labels are mapped to their <h2> headings in the reduced prompt', () {
    final prompt =
        buildResumePrompt(_base, jd, const ['Projects', 'Open Source'], '');
    expect(prompt, contains('Projects and Published Apps'));
    expect(prompt, contains('Open Source Projects'));
    expect(prompt, contains('PROJECTS_UNIQUE_BODY'));
    expect(prompt, contains('OSS_UNIQUE_BODY'));
    // Unrelated sections stay out.
    expect(prompt, isNot(contains('SUMMARY_UNIQUE_BODY')));
    expect(prompt, isNot(contains('EXPERIENCE_UNIQUE_BODY')));
  });

  test('custom instructions are included in the reduced prompt', () {
    final prompt = buildResumePrompt(
        _base, jd, const ['Summary'], 'Emphasize leadership');
    expect(prompt, contains('Emphasize leadership'));
    expect(prompt, contains('USER CUSTOM INSTRUCTIONS'));
  });
}
