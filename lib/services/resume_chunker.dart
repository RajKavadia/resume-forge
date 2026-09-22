import 'gemini_service.dart' show buildResumePrompt;

/// One `<h2>`-bounded resume body section (html includes the opening h2).
class ResumeSection {
  const ResumeSection({required this.heading, required this.html});

  final String heading;
  final String html;
}

/// Pre-h2 header plus content sections from a page fragment / compact HTML.
class SplitPageResult {
  const SplitPageResult({required this.headerHtml, required this.sections});

  /// Markup before the first `<h2>` (name, title, contacts).
  final String headerHtml;
  final List<ResumeSection> sections;
}

/// One per-section generation job when the full prompt exceeds [ResumeChunker.maxPromptTokens].
class ResumeSectionChunkJob {
  const ResumeSectionChunkJob({
    required this.heading,
    required this.sectionHtml,
    required this.prompt,
  });

  final String heading;
  final String sectionHtml;
  final String prompt;
}

/// Either a single full-prompt call or a list of section chunk jobs.
class ResumeChunkPlan {
  const ResumeChunkPlan.full(this.fullPrompt)
      : useFullPrompt = true,
        sectionJobs = const [];

  const ResumeChunkPlan.sections(this.sectionJobs)
      : useFullPrompt = false,
        fullPrompt = null;

  final bool useFullPrompt;
  final String? fullPrompt;
  final List<ResumeSectionChunkJob> sectionJobs;
}

/// Splits oversized resume-tailor prompts by HTML `<h2>` sections.
class ResumeChunker {
  ResumeChunker._();

  static const int maxPromptTokens = 6000;

  /// Default sections when the user does not select any / empty filter.
  static const List<String> defaultOptimizeSections = [
    'Summary',
    'Skills',
    'Experience',
  ];

  static int estimateTokens(String s) => (s.length / 4).ceil();

  static bool needsChunking(String prompt) =>
      estimateTokens(prompt) > maxPromptTokens;

  /// Split compact or page HTML on `<h2>…</h2>`, keeping pre-h2 header separately.
  static SplitPageResult splitPageSections(String compactOrPageHtml) {
    var html = _unwrapPageInner(compactOrPageHtml.trim());
    final h2Re = RegExp(r'<h2\b[^>]*>[\s\S]*?</h2>', caseSensitive: false);
    final matches = h2Re.allMatches(html).toList();
    if (matches.isEmpty) {
      return SplitPageResult(headerHtml: html, sections: const []);
    }

    final headerHtml = html.substring(0, matches.first.start);
    final sections = <ResumeSection>[];
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end =
          i + 1 < matches.length ? matches[i + 1].start : html.length;
      final sectionHtml = html.substring(start, end);
      sections.add(ResumeSection(
        heading: headingText(matches[i].group(0)!),
        html: sectionHtml,
      ));
    }
    return SplitPageResult(headerHtml: headerHtml, sections: sections);
  }

  /// Rebuild a `<div class="page">…</div>` from header + section HTML fragments.
  static String mergeSections(String headerHtml, List<String> sectionHtmls) {
    final buf = StringBuffer()..write(headerHtml);
    for (final s in sectionHtmls) {
      buf.write(s);
    }
    return '<div class="page">${buf.toString()}</div>';
  }

  /// Short per-section prompt (not the full ~70-line builder).
  static String buildSectionPrompt({
    required String baseSectionHtml,
    required String jobDescription,
    required String sectionHeading,
    required String customInstructions,
    String? headerContext,
  }) {
    final custom = customInstructions.trim().isNotEmpty
        ? '\nCUSTOM (highest priority): ${customInstructions.trim()}\n'
        : '';
    final header = (headerContext != null && headerContext.trim().isNotEmpty)
        ? '\nCANDIDATE HEADER (context only — do not output):\n'
            '${headerContext.trim()}\n'
        : '';
    return '''
Rewrite ONLY the "$sectionHeading" resume section for ATS + JD keyword fit.
Rules: stay 100% truthful (no new employers, roles, degrees, or dates); weave JD keywords naturally into existing content; keep HTML tags/classes; return ONLY this section's HTML starting with <h2>…; no markdown fences, no commentary.
$custom$header
SECTION HTML:
$baseSectionHtml

JOB DESCRIPTION:
$jobDescription
''';
  }

  /// When [sectionsToOptimize] is empty and chunking is needed, only the
  /// [defaultOptimizeSections] become jobs. Header is never its own chunk.
  static ResumeChunkPlan planChunks({
    required String compactHtml,
    required String jobDescription,
    required List<String> sectionsToOptimize,
    required String customInstructions,
  }) {
    final effectiveSections = sectionsToOptimize.isEmpty
        ? defaultOptimizeSections
        : sectionsToOptimize;
    final fullPrompt = buildResumePrompt(
      compactHtml,
      jobDescription,
      effectiveSections,
      customInstructions,
    );
    if (!needsChunking(fullPrompt)) {
      return ResumeChunkPlan.full(fullPrompt);
    }

    final split = splitPageSections(compactHtml);
    final jobs = <ResumeSectionChunkJob>[];
    for (final section in split.sections) {
      if (!sectionMatchesFilter(section.heading, effectiveSections)) {
        continue;
      }
      jobs.add(ResumeSectionChunkJob(
        heading: section.heading,
        sectionHtml: section.html,
        prompt: buildSectionPrompt(
          baseSectionHtml: section.html,
          jobDescription: jobDescription,
          sectionHeading: section.heading,
          customInstructions: customInstructions,
          headerContext: split.headerHtml,
        ),
      ));
    }
    return ResumeChunkPlan.sections(jobs);
  }

  /// Empty [filter] → [defaultOptimizeSections].
  /// Matching is case-insensitive; substring either way
  /// (e.g. "Projects" ↔ "Projects and Published Apps").
  static bool sectionMatchesFilter(String heading, List<String> filter) {
    final effective =
        filter.isEmpty ? defaultOptimizeSections : filter;
    final h = heading.toLowerCase().trim();
    for (final raw in effective) {
      final t = raw.toLowerCase().trim();
      if (t.isEmpty) continue;
      if (h == t || h.contains(t) || t.contains(h)) return true;
    }
    return false;
  }

  /// Visible text inside an `<h2>…</h2>` tag.
  static String headingText(String h2Tag) {
    return h2Tag
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  static String _unwrapPageInner(String html) {
    final pageMatch = RegExp(
      r'<div\s+class="page"[^>]*>([\s\S]*)</div\s*>\s*$',
      caseSensitive: false,
    ).firstMatch(html);
    if (pageMatch != null) return pageMatch.group(1)!;

    final bodyMatch = RegExp(
      r'<body[^>]*>([\s\S]*)</body>',
      caseSensitive: false,
    ).firstMatch(html);
    if (bodyMatch != null) {
      final inner = bodyMatch.group(1)!.trim();
      final nested = RegExp(
        r'<div\s+class="page"[^>]*>([\s\S]*)</div\s*>\s*$',
        caseSensitive: false,
      ).firstMatch(inner);
      return nested?.group(1) ?? inner;
    }
    return html;
  }
}
