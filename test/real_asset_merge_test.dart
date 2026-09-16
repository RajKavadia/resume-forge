import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/resume_section_service.dart';

/// Exercises the section parse/merge against the REAL bundled base resume so we
/// know the boundaries in the production HTML are handled correctly (not just
/// the simplified fixtures).
void main() {
  final base = File('assets/Raj_Kavadia_Resume_ATS.html').readAsStringSync();

  test('real asset parses all six sections', () {
    final sections = ResumeSectionService.parseSections(base);
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
  });

  test('merging a tailored Summary preserves head/style/contacts and other sections', () {
    const tailored =
        '<h2>Summary</h2><p>Senior Flutter developer, tailored for the role.</p>';
    final merged = ResumeSectionService.mergeSections(
      base,
      tailored,
      allowedHeadings: ['Summary'],
    );

    // New summary present, old summary text gone.
    expect(merged, contains('tailored for the role'));
    expect(
        merged,
        isNot(contains(
            'Senior Android Engineer with 9+ years of experience building scalable')));

    // Head/style block preserved byte-for-byte (grab a stable style substring).
    expect(merged, contains('font-family: Arial, sans-serif'));
    expect(merged, contains('@page'));
    // Contact block preserved.
    expect(merged, contains('rajkavadia78@gmail.com'));
    expect(merged, contains('github.com/RajKavadia'));

    // Other sections untouched.
    expect(merged, contains('<h2>Skills</h2>'));
    expect(merged, contains('Jetpack Compose, Kotlin Multiplatform'));
    expect(merged, contains('<h2>Experience</h2>'));
    expect(merged, contains('OnlinePSBLoans'));
    expect(merged, contains('<h2>Projects and Published Apps</h2>'));
    expect(merged, contains('Tradgo'));
    expect(merged, contains('<h2>Open Source Projects</h2>'));
    expect(merged, contains('Stratum'));
    expect(merged, contains('<h2>Education</h2>'));
    expect(merged, contains('Gujarat Technological University'));

    // Document ends cleanly.
    expect(merged.trim(), endsWith('</html>'));
    expect(ResumeSectionService.looksLikeDocument(merged), isTrue);
  });

  test('extracting only Summary excludes other sections content', () {
    final headings = ResumeSectionService.headingsForLabels(['Summary']);
    final extracted = ResumeSectionService.extractSections(base, headings);
    expect(extracted, contains('<h2>Summary</h2>'));
    expect(extracted, isNot(contains('<h2>Experience</h2>')));
    expect(extracted, isNot(contains('Tradgo')));
    // Payload is far smaller than the full document.
    expect(extracted.length, lessThan(base.length ~/ 2));
  });
}
