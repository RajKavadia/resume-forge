// Prompt builder retained for NVIDIA NIM; Gemini SDK implementation removed.

import 'nvidia_service.dart';

/// Compatibility facade; generation is now handled by NVIDIA NIM.
class GeminiService {
  static Future<String> tailorResume(
    String jobDescription, {
    required String apiKey,
    List<String> sectionsToOptimize = const [],
    String customInstructions = '',
    String? baseHtmlOverride,
    Future<String> Function(String prompt)? generateOverride,
  }) =>
      NvidiaService.tailorResume(
        jobDescription,
        apiKey: apiKey,
        sectionsToOptimize: sectionsToOptimize,
        customInstructions: customInstructions,
        baseHtmlOverride: baseHtmlOverride,
        generateOverride: generateOverride,
      );
}

/// Compact full-page tailor prompt (token-light after JD brief compression).
String buildResumePrompt(
  String baseHtml,
  String jobDescription,
  List<String> sectionsToOptimize,
  String customInstructions,
) {
  final scope = sectionsToOptimize.isEmpty
      ? 'Skills, Experience'
      : sectionsToOptimize.join(', ');
  final custom = customInstructions.trim().isNotEmpty
      ? '\nCUSTOM (highest priority): ${customInstructions.trim()}\n'
      : '';
  return '''
Tailor this ATS resume HTML to the JOB BRIEF. Stay 100% truthful (no new employers, roles, degrees, or dates).
Optimize ONLY: $scope. Leave all other sections unchanged.
Weave ROLE/KEYWORDS/RESPONSIBILITIES into Summary, Skills, and Experience naturally. Strip "(mandatory)/(preferred)" tags from keywords.
Keep exact HTML structure, h2 headings, and class names. Return ONLY <div class="page">…</div> — no doctype, style, markdown, or commentary.
$custom
BASE HTML:
$baseHtml

JOB BRIEF:
$jobDescription
''';
}
