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

/// One partial HTML tailor job (Skills, first experience entry, etc.).
class ResumeSectionChunkJob {
  const ResumeSectionChunkJob({
    required this.heading,
    required this.sectionHtml,
    required this.prompt,
    required this.mergeId,
    this.isFirstExperienceEntry = false,
  });

  /// UI / progress label (e.g. "Skills", "Experience (first role)").
  final String heading;
  final String sectionHtml;
  final String prompt;
  /// Key in the rewrite map: [mergeIdSkills] or [mergeIdExperienceFirst].
  final String mergeId;
  final bool isFirstExperienceEntry;

  static const mergeIdSkills = 'skills';
  static const mergeIdExperienceFirst = 'experience_first';
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

  /// Tailor pipeline always optimizes Skills + first Experience entry only.
  static const List<String> defaultOptimizeSections = [
    'Skills',
    'Experience',
  ];

  /// First role in Experience (OnlinePSBLoans) — used to locate the entry block.
  static const firstExperienceMarker = 'OnlinePSBLoans';

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

FORMATTED JOB DESCRIPTION (from step 1 — use only this for keywords):
$jobDescription
''';
  }

  static String buildFirstExperienceEntryPrompt({
    required String entryHtml,
    required String jobDescription,
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
Rewrite ONLY this first experience entry (Senior Mobile Application Developer — OnlinePSBLoans, Ahmedabad, Gujarat) for ATS + formatted JD fit.
Rules: stay 100% truthful (no new employers, roles, degrees, or dates); weave JD keywords into bullets; keep HTML classes (entry, entry-header, entry-title, entry-date, entry-sub, ul/li).
Return ONLY one <div class="entry">…</div> — no <h2>, no other jobs, no markdown, no commentary.
$custom$header
ENTRY HTML:
$entryHtml

FORMATTED JOB DESCRIPTION:
$jobDescription
''';
  }

  /// Split `<h2>Experience</h2>` block into first `<div class="entry">` vs the rest.
  static ExperienceEntrySplit? splitFirstExperienceEntry(String experienceSectionHtml) {
    final html = experienceSectionHtml.trim();
    if (!RegExp(r'<h2\b[^>]*>\s*Experience\s*</h2>', caseSensitive: false)
        .hasMatch(html)) {
      return null;
    }
    final entryRe =
        RegExp(r'<div\s+class="entry"[^>]*>', caseSensitive: false);
    final first = entryRe.firstMatch(html);
    if (first == null) return null;

    final firstEntryHtml = _extractBalancedDiv(html, first.start);
    final sectionOpening = html.substring(0, first.start);
    final remainingEntriesHtml = html.substring(first.start + firstEntryHtml.length);
    return ExperienceEntrySplit(
      sectionOpening: sectionOpening,
      firstEntryHtml: firstEntryHtml,
      remainingEntriesHtml: remainingEntriesHtml,
      fullSectionHtml: html,
    );
  }

  /// Replace only the first experience entry; other roles stay unchanged.
  static String mergeFirstExperienceEntry(
    String experienceSectionHtml,
    String newFirstEntryHtml,
  ) {
    final split = splitFirstExperienceEntry(experienceSectionHtml);
    if (split == null) return experienceSectionHtml;
    var entry = newFirstEntryHtml.trim();
    if (!entry.toLowerCase().contains('class="entry"')) {
      entry = '<div class="entry">$entry</div>';
    }
    return '${split.sectionOpening}$entry${split.remainingEntriesHtml}';
  }

  static String _extractBalancedDiv(String html, int start) {
    var i = start;
    var depth = 0;
    while (i < html.length) {
      if (i + 4 <= html.length &&
          html.substring(i, i + 4).toLowerCase() == '<div') {
        depth++;
        i += 4;
        continue;
      }
      if (i + 6 <= html.length &&
          html.substring(i, i + 6).toLowerCase() == '</div>') {
        depth--;
        i += 6;
        if (depth == 0) return html.substring(start, i);
        continue;
      }
      i++;
    }
    throw StateError('Unbalanced <div> in experience section.');
  }

  /// Step 2 jobs only: Skills section + first Experience entry (OnlinePSBLoans).
  static ResumeChunkPlan planPartialSections({
    required String compactHtml,
    required String jobDescription,
    required List<String> sectionsToOptimize,
    required String customInstructions,
  }) {
    final split = splitPageSections(compactHtml);
    final jobs = <ResumeSectionChunkJob>[];

    for (final section in split.sections) {
      if (sectionMatchesFilter(section.heading, const ['Skills'])) {
        jobs.add(ResumeSectionChunkJob(
          heading: 'Skills',
          sectionHtml: section.html,
          mergeId: ResumeSectionChunkJob.mergeIdSkills,
          prompt: buildSectionPrompt(
            baseSectionHtml: section.html,
            jobDescription: jobDescription,
            sectionHeading: section.heading,
            customInstructions: customInstructions,
            headerContext: split.headerHtml,
          ),
        ));
      }
      if (sectionMatchesFilter(section.heading, const ['Experience'])) {
        final expSplit = splitFirstExperienceEntry(section.html);
        if (expSplit != null) {
          jobs.add(ResumeSectionChunkJob(
            heading: 'Experience (first role)',
            sectionHtml: expSplit.firstEntryHtml,
            mergeId: ResumeSectionChunkJob.mergeIdExperienceFirst,
            isFirstExperienceEntry: true,
            prompt: buildFirstExperienceEntryPrompt(
              entryHtml: expSplit.firstEntryHtml,
              jobDescription: jobDescription,
              customInstructions: customInstructions,
              headerContext: split.headerHtml,
            ),
          ));
        }
      }
    }
    return ResumeChunkPlan.sections(jobs);
  }

  /// When [sectionsToOptimize] is empty and chunking is needed, only the
  /// [defaultOptimizeSections] become jobs. Header is never its own chunk.
  static ResumeChunkPlan planChunks({
    required String compactHtml,
    required String jobDescription,
    required List<String> sectionsToOptimize,
    required String customInstructions,
  }) {
    // Prefer partial-section pipeline; only fall back to full prompt if no
    // matching sections exist in the HTML.
    final partial = planPartialSections(
      compactHtml: compactHtml,
      jobDescription: jobDescription,
      sectionsToOptimize: sectionsToOptimize,
      customInstructions: customInstructions,
    );
    if (partial.sectionJobs.isNotEmpty) return partial;

    final effectiveSections = sectionsToOptimize.isEmpty
        ? defaultOptimizeSections
        : sectionsToOptimize;
    final fullPrompt = buildResumePrompt(
      compactHtml,
      jobDescription,
      effectiveSections,
      customInstructions,
    );
    return ResumeChunkPlan.full(fullPrompt);
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

/// First `<div class="entry">` within Experience vs remainder of that section.
class ExperienceEntrySplit {
  const ExperienceEntrySplit({
    required this.sectionOpening,
    required this.firstEntryHtml,
    required this.remainingEntriesHtml,
    required this.fullSectionHtml,
  });

  final String sectionOpening;
  final String firstEntryHtml;
  final String remainingEntriesHtml;
  final String fullSectionHtml;
}
