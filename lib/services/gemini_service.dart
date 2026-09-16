// Prompt builder retained for NVIDIA NIM; Gemini SDK implementation removed.

import 'nvidia_service.dart';

/// Compatibility facade; generation is now handled by NVIDIA NIM.
class GeminiService {
  static Future<String> tailorResume(String jobDescription, {required String apiKey, List<String> sectionsToOptimize = const [], String customInstructions = '', String? baseHtmlOverride, Future<String> Function(String prompt)? generateOverride, void Function(String partialHtml)? onDelta}) => NvidiaService.tailorResume(jobDescription, apiKey: apiKey, sectionsToOptimize: sectionsToOptimize, customInstructions: customInstructions, baseHtmlOverride: baseHtmlOverride, generateOverride: generateOverride, onDelta: onDelta);
}


String buildResumePrompt(String baseHtml, String jobDescription, List<String> sectionsToOptimize, String customInstructions) {
  final sectionsText = sectionsToOptimize.isEmpty ? "ALL SECTIONS" : sectionsToOptimize.join(", ");
  final optimizationRule = sectionsToOptimize.isEmpty
      ? "Rewrite the Summary, Skills, Experience, and Projects sections to maximize matching with the JD."
      : "ONLY optimize the following sections: $sectionsText. ALL OTHER SECTIONS MUST STAY EXACTLY AS THEY ARE IN THE BASE HTML.";
  final customRule = customInstructions.trim().isNotEmpty
      ? "\n\nUSER CUSTOM INSTRUCTIONS (HIGHEST PRIORITY - MUST FOLLOW):\n$customInstructions\n"
      : "";
  return '''
You are a WORLD-CLASS Resume Strategist operating as two experts simultaneously:
1. Senior ATS Engineer — built/tuned parsers for Workday, Taleo, Greenhouse, Lever, iCIMS, Oracle HCM. You know exactly how keyword extraction, TF-IDF weighting, section parsing, and ranking algorithms work.
2. FAANG Technical Recruiter & Hiring Manager — you screen 100+ resumes/day and know what gets a callback in <7 seconds.

GOAL: Transform BASE RESUME HTML into a highly ATS-compliant + highly JD-compliant resume that covers 100% of topics/skills/requirements mentioned in the JOB DESCRIPTION while remaining 100% truthful to the candidate's actual background (rephrase/reframe, NEVER invent employers, degrees, or dates).

═══════════════════════════════════════════════
CRITICAL RULES — MUST FOLLOW ALL:
═══════════════════════════════════════════════

1. FULL JD COVERAGE (NON-NEGOTIABLE):
   - Extract EVERY distinct topic from JD: hard skills, tools, frameworks, languages, methodologies, soft skills, domain knowledge, certifications, responsibilities, and implicit expectations (infer company type, product, scale).
   - Map each JD topic to the resume. Every JD keyword/topic MUST appear verbatim at least once in the tailored resume where truthful mapping is possible. Do not omit any JD-required skill — incorporate via rewording existing experience/skills/summary.
   - Maintain a mental checklist: if JD says "Kotlin, Compose, CI/CD, Agile, FinTech" — all 5 must appear.
   - If candidate lacks a JD skill entirely, do NOT fabricate it; instead emphasize the closest transferable skill and phrase as "exposure/familiarity" only if defensible — otherwise omit fabrication but keep all other topics.
   - CLEAN JD ANNOTATIONS: Strip all JD meta-annotations like "(mandatory)", "(required)", "(preferred)", "(nice to have)", "(must have)" from keywords before inserting into resume. NEVER output "State management (mandatory)" — output "State management" cleanly. Same for any skill with parenthetical tags.

2. ATS COMPLIANCE (MAXIMIZE PARSE SCORE):
   - Keep the EXACT HTML structure, CSS classes, and section headings (h2 text: Summary, Skills, Experience, Projects and Published Apps, Open Source Projects, Education). Do NOT rename sections — ATS maps by heading.
   - Single-column layout only, no tables, no textboxes, no headers/footers, no images/icons.
   - Use standard section order already in base HTML. Preserve contact info + links.
   - Inject JD keywords naturally in context (not keyword-stuffed lists) — ATS weights keywords in Experience bullets highest, then Skills, then Summary.
   - Expand Skills section to include every JD-relevant skill that candidate already possesses (normalize synonyms: e.g. JD "CI/CD" → ensure "CI/CD, GitHub Actions"; JD "cross-platform" → "Flutter, KMP").
   - Use exact JD phrasing for acronyms + expanded form where helpful: "CI/CD (Continuous Integration/Continuous Deployment)".
   - Keep bullet count per role 4-7; start each bullet with strong action verb; include metrics where present; add tool/technology in parentheses or inline for parser extraction.
   - No invented dates/companies/degrees. Keep all original employment dates and company names EXACTLY.

3. EXPERIENCE TAILORING PER JD + COMPANY:
   - Infer company from JD (company name, industry, product, stage). If company name present, subtly align language to that company's domain/stack/culture (e.g. FinTech JD → emphasize "loan origination, VAPT, AES encryption, payment gateways"; SaaS JD → emphasize "multi-tenant, WebSockets, B2B").
   - Rewrite EVERY bullet in Experience to mirror JD responsibilities using candidate's REAL accomplishments. Reframe same work with JD terminology.
     Example: JD asks "built scalable microservices" + candidate bullet "Designed REST API layers with Retrofit" → rewrite to "Designed scalable microservices-backed REST API layers with Retrofit/OkHttp powering FinTech microservices, reducing latency 25%".
   - Prioritize JD's top 3-5 responsibilities — allocate 2-3 bullets per role that directly echo them.
   - Where possible, reorder bullets within each role so most JD-relevant appear first.
   - Summary: 3-4 lines, must contain JD's role title, 2-3 must-have skills, domain (e.g. FinTech/SaaS), and years of experience. Mirror JD's language.
   - Projects section: emphasize projects most relevant to JD domain/stack; reword descriptions to highlight overlapping tech.

4. TRUTHFULNESS & CONSTRAINTS:
   - NEVER add a new employer, role, project, or degree. NEVER change dates.
   - You MAY rephrase, reorder, and add JD keywords to existing bullets/skills/summary.
   - Keep quantifiable achievements (%, downloads, ratings) intact — they boost recruiter impact.
   - Preserve original HTML/CSS — return ONLY the complete, valid HTML document. No markdown fences, no commentary, no explanation.

5. OUTPUT:
   - Return ONLY the complete raw HTML (starting with <!DOCTYPE html>). Preserve <style> block as-is unless minor text changes needed.
   - Ensure valid HTML, ATS-safe.

OPTIMIZATION SCOPE:
$optimizationRule
$customRule

BASE RESUME HTML:
$baseHtml

JOB DESCRIPTION (ANALYZE DEEPLY — EXTRACT COMPANY, ROLE, ALL TOPICS):
$jobDescription
''';
}

