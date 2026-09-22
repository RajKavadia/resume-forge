import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/gemini_service.dart';
import 'package:resumetailor/services/resume_chunker.dart';

void main() {
  const samplePage = '''
<div class="page"><h1>Raj Kavadia</h1><p class="header-title">Senior Android</p>
<div class="header-contacts"><span>Ahmedabad</span></div>
<h2>Summary</h2><p>Senior engineer with Kotlin.</p>
<h2>Skills</h2><div class="skills-list"><p><strong>Mobile:</strong> Flutter</p></div>
<h2>Experience</h2><div class="entry"><p>FinTech role</p></div>
<h2>Projects and Published Apps</h2><div class="entry"><p>Tradgo</p></div>
<h2>Open Source Projects</h2><div class="oss-entry"><strong>Stratum</strong></div>
<h2>Education</h2><div class="edu-entry"><p class="edu-degree">B.E.</p></div></div>
''';

  group('estimateTokens / needsChunking', () {
    test('estimateTokens is ceil(length/4)', () {
      expect(ResumeChunker.estimateTokens(''), 0);
      expect(ResumeChunker.estimateTokens('abcd'), 1);
      expect(ResumeChunker.estimateTokens('abcde'), 2);
      expect(ResumeChunker.estimateTokens('a' * 24), 6);
    });

    test('needsChunking uses maxPromptTokens=6000', () {
      expect(ResumeChunker.maxPromptTokens, 6000);
      final under = 'x' * (6000 * 4); // exactly 6000 tokens
      final over = 'x' * (6000 * 4 + 1);
      expect(ResumeChunker.needsChunking(under), isFalse);
      expect(ResumeChunker.needsChunking(over), isTrue);
    });
  });

  group('split / merge', () {
    test('splitPageSections extracts header and six h2 sections', () {
      final split = ResumeChunker.splitPageSections(samplePage);
      expect(split.headerHtml.contains('Raj Kavadia'), isTrue);
      expect(split.headerHtml.contains('<h2'), isFalse);
      expect(split.sections.map((s) => s.heading).toList(), [
        'Summary',
        'Skills',
        'Experience',
        'Projects and Published Apps',
        'Open Source Projects',
        'Education',
      ]);
      expect(split.sections.first.html.startsWith('<h2>Summary</h2>'), isTrue);
      expect(split.sections[3].html.contains('Tradgo'), isTrue);
    });

    test('mergeSections roundtrips with split', () {
      final split = ResumeChunker.splitPageSections(samplePage);
      final merged = ResumeChunker.mergeSections(
        split.headerHtml,
        split.sections.map((s) => s.html).toList(),
      );
      expect(merged.startsWith('<div class="page">'), isTrue);
      expect(merged.endsWith('</div>'), isTrue);
      expect(merged.contains('<h1>Raj Kavadia</h1>'), isTrue);
      expect(merged.contains('<h2>Education</h2>'), isTrue);
      expect(merged.contains('Tradgo'), isTrue);

      final again = ResumeChunker.splitPageSections(merged);
      expect(again.sections.length, split.sections.length);
      for (var i = 0; i < split.sections.length; i++) {
        expect(again.sections[i].heading, split.sections[i].heading);
        expect(again.sections[i].html, split.sections[i].html);
      }
    });
  });

  group('section filter / planChunks', () {
    test('sectionMatchesFilter empty uses default core sections', () {
      expect(ResumeChunker.sectionMatchesFilter('Summary', const []), isTrue);
      expect(ResumeChunker.sectionMatchesFilter('Skills', const []), isTrue);
      expect(ResumeChunker.sectionMatchesFilter('Experience', const []), isTrue);
      expect(ResumeChunker.sectionMatchesFilter('Education', const []), isFalse);
      expect(
        ResumeChunker.sectionMatchesFilter(
          'Projects and Published Apps',
          const ['Projects'],
        ),
        isTrue,
      );
      expect(
        ResumeChunker.sectionMatchesFilter('Education', const ['Skills']),
        isFalse,
      );
    });

    test('planChunks returns full mode when prompt is under limit', () {
      final plan = ResumeChunker.planChunks(
        compactHtml: samplePage,
        jobDescription: 'Flutter developer',
        sectionsToOptimize: const ['Summary'],
        customInstructions: '',
      );
      expect(plan.useFullPrompt, isTrue);
      expect(plan.fullPrompt, isNotNull);
      expect(plan.sectionJobs, isEmpty);
      expect(plan.fullPrompt!, contains('Summary'));
      expect(plan.fullPrompt!, contains('Flutter developer'));
    });

    test('planChunks filters section jobs when forced over limit', () {
      // Inflate JD so buildResumePrompt exceeds 6000 tokens.
      final hugeJd = 'REQUIREMENT ${'Kotlin Flutter CI/CD ' * 2000}';
      expect(
        ResumeChunker.needsChunking(
          buildResumePrompt(samplePage, hugeJd, const ['Summary', 'Skills'], ''),
        ),
        isTrue,
      );

      final plan = ResumeChunker.planChunks(
        compactHtml: samplePage,
        jobDescription: hugeJd,
        sectionsToOptimize: const ['Summary', 'Skills'],
        customInstructions: 'Keep metrics',
      );
      expect(plan.useFullPrompt, isFalse);
      expect(plan.sectionJobs.map((j) => j.heading).toList(),
          ['Summary', 'Skills']);
      for (final job in plan.sectionJobs) {
        expect(job.prompt.contains('<h2>${job.heading}</h2>'), isTrue);
        expect(job.prompt.contains('Keep metrics'), isTrue);
        expect(job.prompt.contains('return ONLY this section'), isTrue);
        expect(job.sectionHtml.startsWith('<h2>'), isTrue);
      }
    });

    test('planChunks with empty filter emits default core sections only', () {
      final hugeJd = 'JD ${'x' * 30000}';
      final plan = ResumeChunker.planChunks(
        compactHtml: samplePage,
        jobDescription: hugeJd,
        sectionsToOptimize: const [],
        customInstructions: '',
      );
      expect(plan.useFullPrompt, isFalse);
      expect(plan.sectionJobs.map((j) => j.heading).toList(), [
        'Summary',
        'Skills',
        'Experience',
      ]);
    });
  });

  group('buildSectionPrompt', () {
    test('asks for h2-only output and includes header context', () {
      final prompt = ResumeChunker.buildSectionPrompt(
        baseSectionHtml: '<h2>Summary</h2><p>old</p>',
        jobDescription: 'Need Compose',
        sectionHeading: 'Summary',
        customInstructions: '',
        headerContext: '<h1>Raj</h1>',
      );
      expect(prompt, contains('starting with <h2>'));
      expect(prompt, contains('Need Compose'));
      expect(prompt, contains('<h1>Raj</h1>'));
      expect(prompt, isNot(contains('WORLD-CLASS Resume Strategist')));
    });
  });
}
