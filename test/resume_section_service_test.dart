import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/resume_section_service.dart';

const _fixture = '''
<!DOCTYPE html><html><head><style>h2{color:#000}</style></head><body><div class="page">
<h1>Jane Doe</h1>
<p class="header-title">Engineer</p>
<div class="header-contacts"><span>jane@example.com</span></div>
<h2>Summary</h2><p>SUMMARY_ORIGINAL_TEXT</p>
<h2>Skills</h2><div class="skills-list"><p>SKILLS_ORIGINAL_TEXT</p></div>
<h2>Experience</h2><div class="entry"><ul><li>EXPERIENCE_ORIGINAL_TEXT</li></ul></div>
<h2>Projects and Published Apps</h2><div class="entry"><p>PROJECTS_ORIGINAL_TEXT</p></div>
<h2>Open Source Projects</h2><div class="oss-entry">OSS_ORIGINAL_TEXT</div>
<h2>Education</h2><div class="edu-entry">EDUCATION_ORIGINAL_TEXT</div>
</div></body></html>''';

void main() {
  group('label mapping', () {
    test('maps divergent UI labels to their <h2> headings', () {
      expect(ResumeSectionService.headingForLabel('Projects'),
          equals('Projects and Published Apps'));
      expect(ResumeSectionService.headingForLabel('Open Source'),
          equals('Open Source Projects'));
    });

    test('maps identical labels to themselves', () {
      expect(ResumeSectionService.headingForLabel('Summary'), equals('Summary'));
      expect(ResumeSectionService.headingForLabel('Skills'), equals('Skills'));
      expect(
          ResumeSectionService.headingForLabel('Experience'), equals('Experience'));
      expect(
          ResumeSectionService.headingForLabel('Education'), equals('Education'));
    });

    test('headingsForLabels preserves order and dedupes', () {
      final headings = ResumeSectionService.headingsForLabels(
          ['Summary', 'Projects', 'Summary', 'Open Source']);
      expect(headings,
          equals(['Summary', 'Projects and Published Apps', 'Open Source Projects']));
    });
  });

  group('parseSections', () {
    test('extracts every <h2> section keyed by heading text', () {
      final sections = ResumeSectionService.parseSections(_fixture);
      expect(
        sections.keys,
        containsAll(<String>[
          'Summary',
          'Skills',
          'Experience',
          'Projects and Published Apps',
          'Open Source Projects',
          'Education',
        ]),
      );
      expect(sections['Summary'], contains('SUMMARY_ORIGINAL_TEXT'));
      expect(sections['Summary'], startsWith('<h2>Summary</h2>'));
      // A section fragment should not bleed into the next section.
      expect(sections['Summary'], isNot(contains('SKILLS_ORIGINAL_TEXT')));
      expect(sections['Education'], contains('EDUCATION_ORIGINAL_TEXT'));
      expect(sections['Education'], isNot(contains('OSS_ORIGINAL_TEXT')));
    });
  });

  group('extractSections', () {
    test('returns only requested sections in document order', () {
      final headings = ResumeSectionService.headingsForLabels(['Projects']);
      final extracted = ResumeSectionService.extractSections(_fixture, headings);
      expect(extracted, contains('Projects and Published Apps'));
      expect(extracted, contains('PROJECTS_ORIGINAL_TEXT'));
      expect(extracted, isNot(contains('SUMMARY_ORIGINAL_TEXT')));
      expect(extracted, isNot(contains('EXPERIENCE_ORIGINAL_TEXT')));
    });
  });

  group('mergeSections', () {
    test('replaces only the tailored section, leaving others unchanged', () {
      const tailored =
          '<h2>Summary</h2><p>SUMMARY_TAILORED_TEXT with Kotlin and Flutter</p>';
      final merged = ResumeSectionService.mergeSections(
        _fixture,
        tailored,
        allowedHeadings: ['Summary'],
      );
      expect(merged, contains('SUMMARY_TAILORED_TEXT'));
      expect(merged, isNot(contains('SUMMARY_ORIGINAL_TEXT')));
      // Other sections untouched.
      expect(merged, contains('SKILLS_ORIGINAL_TEXT'));
      expect(merged, contains('EXPERIENCE_ORIGINAL_TEXT'));
      expect(merged, contains('PROJECTS_ORIGINAL_TEXT'));
      expect(merged, contains('OSS_ORIGINAL_TEXT'));
      expect(merged, contains('EDUCATION_ORIGINAL_TEXT'));
      // Head/style/contact block preserved.
      expect(merged, contains('<style>h2{color:#000}</style>'));
      expect(merged, contains('jane@example.com'));
    });

    test('ignores sections not in allowedHeadings', () {
      const tailored =
          '<h2>Summary</h2><p>NEW_SUMMARY</p><h2>Skills</h2><p>NEW_SKILLS</p>';
      final merged = ResumeSectionService.mergeSections(
        _fixture,
        tailored,
        allowedHeadings: ['Summary'],
      );
      expect(merged, contains('NEW_SUMMARY'));
      // Skills was not allowed, so its original stays.
      expect(merged, contains('SKILLS_ORIGINAL_TEXT'));
      expect(merged, isNot(contains('NEW_SKILLS')));
    });

    test('merged output is still a valid document', () {
      const tailored = '<h2>Summary</h2><p>NEW</p>';
      final merged = ResumeSectionService.mergeSections(_fixture, tailored,
          allowedHeadings: ['Summary']);
      expect(ResumeSectionService.looksLikeDocument(merged), isTrue);
    });
  });
}
