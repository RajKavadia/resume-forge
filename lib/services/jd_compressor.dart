/// Compresses a raw screen-dump / job posting into a token-efficient brief
/// (keywords, responsibilities, key points) for resume tailoring.
class JdBrief {
  const JdBrief({
    required this.role,
    required this.company,
    required this.keywords,
    required this.responsibilities,
    required this.keyPoints,
    required this.rawModelOut,
  });

  final String role;
  final String company;
  final List<String> keywords;
  final List<String> responsibilities;
  final List<String> keyPoints;
  final String rawModelOut;

  bool get isEmpty =>
      keywords.isEmpty &&
      responsibilities.isEmpty &&
      keyPoints.isEmpty &&
      role.trim().isEmpty;

  /// Compact text fed into resume prompts (far fewer tokens than a screen dump).
  String toPromptBrief() {
    final buf = StringBuffer();
    if (role.trim().isNotEmpty) buf.writeln('ROLE: ${role.trim()}');
    if (company.trim().isNotEmpty) buf.writeln('COMPANY: ${company.trim()}');
    if (keywords.isNotEmpty) {
      buf.writeln('KEYWORDS: ${keywords.join(', ')}');
    }
    if (responsibilities.isNotEmpty) {
      buf.writeln('RESPONSIBILITIES:');
      for (final r in responsibilities) {
        buf.writeln('- $r');
      }
    }
    if (keyPoints.isNotEmpty) {
      buf.writeln('KEY POINTS:');
      for (final p in keyPoints) {
        buf.writeln('- $p');
      }
    }
    final out = buf.toString().trim();
    return out.isNotEmpty ? out : rawModelOut.trim();
  }
}

class JdCompressor {
  JdCompressor._();

  /// Max chars of screen dump sent to the compressor (pre-trim).
  static const maxScreenDumpChars = 14000;

  /// Soft cap for the brief used in resume prompts.
  static const maxBriefChars = 2800;

  static const maxCompressTokens = 500;

  /// Skip the compress API call when the dump is already this small (tokens).
  static const skipCompressMaxTokens = 1500;

  static const systemPrompt =
      'Format the job posting into the labeled fields below. Return ONLY that formatted job description. No markdown fences, no commentary.';

  static int estimateTokens(String s) => (s.length / 4).ceil();

  static bool shouldSkipCompress(String screenDump) =>
      estimateTokens(trimScreenDump(screenDump)) <= skipCompressMaxTokens;

  static String buildCompressPrompt(String screenDump) {
    final dump = trimScreenDump(screenDump);
    return '''
Format this job-posting / accessibility screen dump into a clean job description for resume tailoring (step 1 — do not rewrite the resume).
Strip UI chrome, ads, nav, cookies, "easy apply", salary widgets, and duplicate lines.
Extract ONLY:
1) keywords / skills / tools / stack (verbatim JD phrasing where possible)
2) key responsibilities
3) key points (must-haves, seniority, domain, location type)

Return EXACTLY this layout (omit a section only if truly absent):

ROLE: <job title>
COMPANY: <company or Unknown>
KEYWORDS: <comma-separated, max 40>
RESPONSIBILITIES:
- <max 12 short bullets>
KEY POINTS:
- <max 8 short bullets>

SCREEN DUMP:
$dump
''';
  }

  static String trimScreenDump(String raw) {
    var t = raw.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    if (t.length > maxScreenDumpChars) {
      t =
          '${t.substring(0, maxScreenDumpChars)}… [truncated ${raw.length - maxScreenDumpChars} chars]';
    }
    return t;
  }

  /// Parse model output into [JdBrief]. Tolerant of minor label variants.
  static JdBrief parse(String modelOut) {
    final text = modelOut
        .replaceAll(RegExp(r'```[a-zA-Z]*\s*'), '')
        .replaceAll('```', '')
        .trim();
    final role = _fieldLine(text, 'ROLE');
    final company = _fieldLine(text, 'COMPANY');
    final keywordsRaw = _fieldLine(text, 'KEYWORDS');
    final keywords = keywordsRaw
        .split(RegExp(r'[,;|]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(40)
        .toList();
    final responsibilities = _bulletSection(text, 'RESPONSIBILITIES');
    final keyPoints = _bulletSection(text, 'KEY POINTS');
    return JdBrief(
      role: role,
      company: company,
      keywords: keywords,
      responsibilities: responsibilities.take(12).toList(),
      keyPoints: keyPoints.take(8).toList(),
      rawModelOut: text,
    );
  }

  /// Prefer parsed brief; if empty/too thin, fall back to a hard-trimmed dump.
  static String briefOrFallback(String modelOut, String originalDump) {
    final brief = parse(modelOut);
    var out = brief.toPromptBrief();
    if (brief.isEmpty || out.length < 40) {
      out = trimScreenDump(originalDump);
      // Collapse whitespace harder for fallback.
      out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    if (out.length > maxBriefChars) {
      out = '${out.substring(0, maxBriefChars)}…';
    }
    return out;
  }

  static String _fieldLine(String text, String label) {
    final re = RegExp(
      '^$label\\s*:\\s*(.*)\\s*\$',
      multiLine: true,
      caseSensitive: false,
    );
    final m = re.firstMatch(text);
    return m?.group(1)?.trim() ?? '';
  }

  static List<String> _bulletSection(String text, String label) {
    final startInline = RegExp(
      '^$label\\s*:\\s*(.*)\\s*\$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(text);
    if (startInline == null) return const [];

    final from = startInline.start;
    final afterHeader = startInline.end;
    final rest = text.substring(afterHeader);
    final nextHeader = RegExp(
      r'^(ROLE|COMPANY|KEYWORDS|RESPONSIBILITIES|KEY POINTS)\s*:',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(rest);
    final block = nextHeader == null
        ? text.substring(from)
        : text.substring(from, afterHeader + nextHeader.start);

    final lines = block.split('\n');
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (i == 0) {
        // Drop the "LABEL:" prefix from first line; keep remainder if any.
        line = line.replaceFirst(
          RegExp('^$label\\s*:', caseSensitive: false),
          '',
        ).trim();
      }
      if (line.isEmpty) continue;
      if (RegExp(r'^(ROLE|COMPANY|KEYWORDS|RESPONSIBILITIES|KEY POINTS)\s*:',
              caseSensitive: false)
          .hasMatch(line)) {
        continue;
      }
      line = line.replaceFirst(RegExp(r'^[-*•]\s*'), '').trim();
      if (line.isNotEmpty) out.add(line);
    }
    return out;
  }
}
