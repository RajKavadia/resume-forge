import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  /// Calls Gemini to tailor the resume HTML for the provided [jobDescription].
  ///
  /// Pass [apiKey] from user input (do not bundle it in assets).
  ///
  /// For tests, you can provide [baseHtmlOverride] and/or [generateOverride]
  /// to avoid network calls.
  /// Calls Gemini to tailor the resume HTML for the provided [jobDescription].
  ///
  /// [sectionsToOptimize] specifies which parts of the resume should be tailored.
  /// If empty, it defaults to optimizing everything.
  static Future<String> tailorResume(String jobDescription, {
    required String apiKey,
    List<String> sectionsToOptimize = const [],
    String customInstructions = '',
    String? baseHtmlOverride,
    Future<String> Function(String prompt)? generateOverride,
  }) async {
    developer.log(
      'Starting tailorResume',
      name: 'ResumeForge.GeminiService',
      error: {
        'jobDescriptionLength': jobDescription.length,
        'sectionsToOptimize': sectionsToOptimize,
        'hasCustomInstructions': customInstructions.isNotEmpty,
      },
    );
    if (apiKey
        .trim()
        .isEmpty) {
      throw Exception('API key is required.');
    }

    final String baseHtml = baseHtmlOverride ??
        await rootBundle.loadString('assets/Raj_Kavadia_Resume_ATS.html');

    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey.trim(),
    );

    final prompt = _buildPrompt(baseHtml, jobDescription, sectionsToOptimize, customInstructions);
    final raw = generateOverride != null
        ? await generateOverride(prompt)
        : (await model.generateContent([Content.text(prompt)])).text ?? '';

    developer.log(
      'Gemini returned response',
      name: 'ResumeForge.GeminiService',
      error: {'responseLength': raw.length},
    );
    return _stripMarkdownFences(raw);
  }

  static String _buildPrompt(String baseHtml, String jobDescription, List<String> sectionsToOptimize, String customInstructions) {
    return buildResumePrompt(baseHtml, jobDescription, sectionsToOptimize, customInstructions);
  }

  static String _stripMarkdownFences(String text) {
    return text
        .replaceAll(RegExp(r'```html\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();
  }
}

String buildResumePrompt(String baseHtml, String jobDescription, List<String> sectionsToOptimize, String customInstructions) {
  final sectionsText = sectionsToOptimize.isEmpty 
      ? "ALL SECTIONS" 
      : sectionsToOptimize.join(", ");
  
  final optimizationRule = sectionsToOptimize.isEmpty
      ? "Rewrite the Summary, Skills, Experience, and Projects sections to maximize matching with the JD."
      : "ONLY optimize the following sections: $sectionsText. ALL OTHER SECTIONS MUST STAY EXACTLY AS THEY ARE IN THE BASE HTML.";

  final customRule = customInstructions.trim().isNotEmpty
      ? "\n\nUSER CUSTOM INSTRUCTIONS (PRIORITIZE THESE):\n$customInstructions\n"
      : "";

  return '''
You are a dual-expert system combining:
- A Senior ATS Engineer who has built and tuned ATS parsers (Workday, Taleo, Greenhouse, Lever, iCIMS)
- A Technical Recruiter with experience at top tech firms (Google, Meta, OpenAI)

YOUR TASK:
Analyse the JOB DESCRIPTION and rewrite the BASE RESUME HTML to maximise both ATS parse score AND human recruiter impact.

OPTIMIZATION SCOPE:
$optimizationRule
$customRule

════════════════════════════════════════
PHASE 1 — JD DECONSTRUCTION (internal reasoning, not output)
════════════════════════════════════════
Before rewriting, mentally extract:
  A. HARD REQUIREMENTS  — Must-have skills, tools, years of experience, degrees
  B. SOFT REQUIREMENTS  — Preferred/nice-to-have from "preferred" or "bonus" sections
  C. POWER VERBS        — Action verbs the JD itself uses (mirror these exactly)
  D. CULTURE SIGNALS    — Words like "fast-paced", "collaborative", "ownership", "scale"
  E. METRIC TYPES       — What does this role measure? (latency, revenue, DAU, uptime, NPS…)
  F. SENIORITY SIGNALS  — Leadership, mentorship, cross-functional, strategic indicators

════════════════════════════════════════
PHASE 2 — ATS TECHNICAL RULES
════════════════════════════════════════
1. KEYWORD DENSITY: Integrate the top 20 ATS keywords naturally. Each hard requirement keyword must appear AT LEAST TWICE across the document (once in Skills, once in Experience/Summary).
2. EXACT-MATCH STRINGS: Use the JD's exact phrasing for tools and technologies (e.g. if JD says "React.js", do not write "ReactJS" or "React").
3. SKILLS TAXONOMY: Reorder skill categories — most JD-critical skills FIRST. Add any genuinely applicable missing keywords.
4. TITLE MIRRORING: If the candidate's current/past titles are close but not exact to the JD title, add the JD title in parentheses where contextually honest — e.g. "Senior Engineer (Full-Stack)".
5. NO ATS TRAPS: Never use tables, columns, headers/footers, text boxes, or images to hold key information — ATS parsers skip them. (Apply only if the HTML structure allows; do not break the layout.)

════════════════════════════════════════
PHASE 3 — CONTENT REWRITING RULES
════════════════════════════════════════
6. SUMMARY — Rewrite as a 3-sentence executive pitch:
   • Sentence 1: Years of experience + exact JD title + top 2 hard skills from JD
   • Sentence 2: Most impressive quantified achievement relevant to THIS role
   • Sentence 3: Mirror 2 culture/seniority signals from the JD

7. EXPERIENCE BULLETS — Use the CAR+M formula:
   CONTEXT → ACTION → RESULT + METRIC
   - Start every bullet with a JD power verb (from your Phase 1 extraction)
   - Each bullet must contain at least one number, %, \$, or scale indicator
   - Replace weak verbs (worked on, helped, assisted, involved) with strong ones
   - Prioritise bullets that map to hard requirements; move or compress unrelated ones

8. PROJECTS — Lead with the most JD-relevant project. Rewrite bullets to surface:
   - Technologies that exactly match JD keywords
   - Scale or impact metrics
   - Problem → Solution → Outcome structure

9. EDUCATION — If JD mentions preferred degrees or certifications, ensure they are prominently visible and keyword-matched.

════════════════════════════════════════
PHASE 4 — RAJ'S UNIQUE VALUE PROPOSITIONS (Must highlight if relevant to JD)
════════════════════════════════════════
10. AI-ASSISTED DEVELOPMENT: Strongly highlight the use of Claude, MCP (Model Context Protocol), and AI-driven automation (Playwright/Node.js) if the JD mentions "productivity," "modern tools," or "innovation."
11. MASSIVE SCALE: Emphasize the "50L+ downloads" for SBI/PNB/Tradgo apps when applying to high-scale or enterprise roles.
12. ARCHITECTURAL LEADERSHIP: Focus on "Multi-module architecture," "Clean Architecture," and "Mentoring 5+ engineers" for Senior/Lead roles.

════════════════════════════════════════
PHASE 5 — ABSOLUTE CONSTRAINTS
════════════════════════════════════════
13. PRESERVE STRUCTURE: Return the COMPLETE HTML. Do NOT alter any HTML tags, CSS classes, inline styles, or the <style> block.
14. PRESERVE IDENTITY: Do NOT change name, contact info, company names, job titles, or dates.
15. ZERO HALLUCINATION: Do NOT invent roles, companies, projects, degrees, certifications, or metrics. Only reframe what genuinely exists.
16. OUTPUT FORMAT: Return ONLY raw HTML starting with <!DOCTYPE html> and ending with </html>. No markdown. No commentary. No preamble.

BASE RESUME HTML:
$baseHtml

JOB DESCRIPTION:
$jobDescription
''';
}
