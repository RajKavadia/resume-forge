// Prompt builder retained for NVIDIA NIM; Gemini SDK implementation removed.

import 'nvidia_service.dart';
import 'resume_section_service.dart';

/// Compatibility facade; generation is now handled by NVIDIA NIM.
class GeminiService {
  static Future<String> tailorResume(String jobDescription, {required String apiKey, List<String> sectionsToOptimize = const [], String customInstructions = '', String? baseHtmlOverride, Future<String> Function(String prompt)? generateOverride, void Function(String partialHtml)? onDelta, String? providerId}) => NvidiaService.tailorResume(jobDescription, apiKey: apiKey, sectionsToOptimize: sectionsToOptimize, customInstructions: customInstructions, baseHtmlOverride: baseHtmlOverride, generateOverride: generateOverride, onDelta: onDelta, providerId: providerId);
}


String buildResumePrompt(String baseHtml, String jobDescription, List<String> sectionsToOptimize, String customInstructions) {
  // Reduced-payload path: when specific sections are requested, embed ONLY the
  // requested section fragments (mapped to their <h2> headings) and ask the
  // model to return ONLY those tailored fragments. The caller merges them back
  // into the full base HTML on-device. This keeps the upload/download small.
  if (sectionsToOptimize.isNotEmpty) {
    return _buildReducedPrompt(baseHtml, jobDescription, sectionsToOptimize, customInstructions);
  }
  final optimizationRule =
      "Rewrite the Summary, Skills, Experience, and Projects sections to maximize matching with the JD.";
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


/// Builds a reduced-payload prompt for the section-scoped tailoring path.
///
/// Only the HTML fragments for the requested sections (resolved from the UI
/// labels to their `<h2>` headings) are embedded, together with the JD and any
/// custom instructions. The model is asked to return ONLY the tailored section
/// fragments — each wrapped by its original `<h2>...</h2>` heading — which the
/// caller then merges back into the full base HTML on-device.
String _buildReducedPrompt(String baseHtml, String jobDescription, List<String> sectionsToOptimize, String customInstructions) {
  final headings = ResumeSectionService.headingsForLabels(sectionsToOptimize);
  final sectionFragments = ResumeSectionService.extractSections(baseHtml, headings);
  // If none of the requested sections could be resolved from the base HTML,
  // fall back to embedding the full document so we never send an empty prompt.
  final embedded = sectionFragments.trim().isEmpty ? baseHtml : sectionFragments;
  final headingList = headings.isEmpty ? sectionsToOptimize.join(', ') : headings.join(', ');
  final customRule = customInstructions.trim().isNotEmpty
      ? "\n\nUSER CUSTOM INSTRUCTIONS (HIGHEST PRIORITY - MUST FOLLOW):\n$customInstructions\n"
      : "";
  return '''
You are a WORLD-CLASS Resume Strategist operating as two experts simultaneously:
1. Senior ATS Engineer — you know exactly how ATS keyword extraction, TF-IDF weighting, section parsing, and ranking algorithms work.
2. FAANG Technical Recruiter & Hiring Manager — you know what earns a callback in <7 seconds.

GOAL: Tailor ONLY the resume sections provided below so they cover 100% of the relevant topics/skills/requirements in the JOB DESCRIPTION while staying 100% truthful (rephrase/reframe existing content, NEVER invent employers, degrees, dates, or projects).

═══════════════════════════════════════════════
CRITICAL RULES — MUST FOLLOW ALL:
═══════════════════════════════════════════════

1. SCOPE — RETURN ONLY THESE SECTIONS: $headingList
   - You are given ONLY these section fragments (not the whole resume). Do NOT invent or output any other section.
   - Keep the EXACT `<h2>` heading text for each section unchanged (ATS maps by heading). Do NOT rename sections.

2. FULL JD COVERAGE (within the provided sections):
   - Extract every distinct JD topic: hard skills, tools, frameworks, languages, methodologies, soft skills, domain knowledge, responsibilities.
   - Insert every truthfully-mappable JD keyword verbatim into the provided sections where it fits naturally (weight Experience bullets highest, then Skills, then Summary).
   - Strip JD meta-annotations like "(mandatory)", "(required)", "(preferred)", "(nice to have)" before inserting keywords.
   - Do NOT fabricate skills the candidate lacks; emphasize closest transferable experience instead.

3. ATS COMPLIANCE:
   - Preserve the EXACT HTML structure, CSS classes, and element hierarchy inside each section. Single-column only; no tables, images, or icons.
   - Keep all original employment dates, company names, metrics, and links EXACTLY. Never change dates or invent roles.
   - Bullets: strong action verbs, 4-7 per role, mirror JD responsibilities using the candidate's real accomplishments; reorder most-JD-relevant first.
   - Summary (if provided): 3-4 lines including the JD role title, 2-3 must-have skills, domain, and years of experience.

4. TRUTHFULNESS:
   - You MAY rephrase, reorder, and add JD keywords to existing bullets/skills/summary. You may NOT add new employers, roles, projects, or degrees.

5. OUTPUT (STRICT):
   - Return ONLY the tailored section fragments, each starting with its original `<h2>...</h2>` heading followed by that section's tailored HTML content.
   - Return them in the same order they appear below.
   - Do NOT return `<!DOCTYPE html>`, `<html>`, `<head>`, `<style>`, `<body>`, or any other section. Do NOT wrap output in markdown fences. No commentary or explanation.
$customRule

SECTIONS TO TAILOR (RETURN ONLY THESE, KEEP THEIR `<h2>` HEADINGS):
$embedded

JOB DESCRIPTION (ANALYZE DEEPLY — EXTRACT COMPANY, ROLE, ALL TOPICS):
$jobDescription
''';
}

