import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'gemini_service.dart' show buildResumePrompt;
import 'jd_compressor.dart';
import 'nvidia_api_key_rotator.dart';
import 'nvidia_stream_client.dart';
import 'resume_chunker.dart';

class NvidiaService {
  static const endpoint = 'https://integrate.api.nvidia.com/v1/chat/completions';
  static const defaultModel = 'openai/gpt-oss-20b';

  /// Fast/small model for JD screen-dump compression only.
  static const compressModel = 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning';

  static const List<String> defaultOptimizeSections =
      ResumeChunker.defaultOptimizeSections;

  // --- Speed tuning ---
  static const maxJdChars = 4000;
  static const maxTokens = 2500;
  /// Sequential section calls (JD compress first, then one section at a time).
  static const sectionConcurrency = 1;
  static const perRequestTimeout = Duration(seconds: 60);

  static const _pageSystem =
      'Return only a complete <div class="page">...</div> resume fragment. No doctype, style, markdown, or commentary.';
  static const _sectionSystem =
      'Return only one resume section starting with <h2>…</h2>. No page wrapper, doctype, style, markdown, or commentary.';
  static const _entrySystem =
      'Return only one <div class="entry">…</div> experience block. No h2, page wrapper, markdown, or commentary.';

  static const _modelFallbacks = [
    'openai/gpt-oss-20b',
    'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',
    'mistralai/mistral-large-2-instruct',
    'nvidia/nemotron-3-super-120b-a12b',
  ];

  // Tiny in-memory caches.
  static final Map<int, String> _cache = <int, String>{};
  static final Map<int, String> _briefCache = <int, String>{};
  static const _cacheMaxEntries = 20;
  static const _briefCacheMaxEntries = 40;
  // Bump when JD→partial-section sequential pipeline changes.
  static const _cacheVersion = 8;

  static Future<String> tailorResume(
    String jobDescription, {
    required String apiKey,
    String? endpointOverride,
    String? modelOverride,
    List<String> sectionsToOptimize = const [],
    String customInstructions = '',
    String? baseHtmlOverride,
    Future<String> Function(String prompt)? generateOverride,
    void Function(String stage)? onProgress,
  }) async {
    final effEndpoint = (endpointOverride?.trim().isNotEmpty == true)
        ? endpointOverride!.trim()
        : endpoint;
    final isLocal = _isLocalEndpoint(effEndpoint);
    final effKey = apiKey.trim().isEmpty && isLocal ? 'ollama' : apiKey.trim();
    final keys = parseKeys(effKey);
    if (keys.isEmpty) throw Exception('API key is required.');

    final screenDump = JdCompressor.trimScreenDump(jobDescription);
    if (screenDump.isEmpty) {
      throw Exception('Job description is empty after trimming.');
    }

    final primary = (modelOverride?.trim().isNotEmpty == true)
        ? modelOverride!.trim()
        : defaultModel;
    final effectiveSections = sectionsToOptimize.isEmpty
        ? defaultOptimizeSections
        : sectionsToOptimize;

    // Tests / mocks: skip network compress; use trimmed dump as JD.
    late final String jd;
    if (generateOverride != null) {
      jd = trimJd(screenDump);
    } else {
      // Step 1 (always): optimize / compress the job description first.
      jd = await _resolveJobBrief(
        screenDump: screenDump,
        keys: keys,
        endpoint: effEndpoint,
        tailorModel: primary,
        onProgress: onProgress,
        forceCompress: true,
      );
    }
    if (jd.isEmpty) throw Exception('Job description is empty after trimming.');

    final baseHtml = baseHtmlOverride ??
        await rootBundle.loadString('assets/Raj_Kavadia_Resume_ATS.html');
    final compactBase = compactHtml(baseHtml);
    // Step 2+: partial Skills/Experience HTML only — never full-page generation.
    final plan = ResumeChunker.planPartialSections(
      compactHtml: compactBase,
      jobDescription: jd,
      sectionsToOptimize: effectiveSections,
      customInstructions: customInstructions,
    );
    final promptForOverride = plan.sectionJobs.isNotEmpty
        ? plan.sectionJobs.map((j) => j.prompt).join('\n\n---\n\n')
        : buildResumePrompt(
            compactBase, jd, effectiveSections, customInstructions);

    if (generateOverride != null) {
      final raw2 = await generateOverride(promptForOverride);
      developer.log('NVIDIA returned response',
          name: 'ResumeForge.NvidiaService',
          error: {'responseLength': raw2.length});
      return finalizeHtml(clean(raw2), baseHtml);
    }

    final cacheKey = _cacheKey(
        jd: jd,
        model: primary,
        endpoint: effEndpoint,
        sections: effectiveSections,
        custom: customInstructions);
    final cached = _cache[cacheKey];
    if (cached != null) {
      developer.log('tailor cache hit',
          name: 'ResumeForge.NvidiaService',
          error: {'model': primary, 'htmlLength': cached.length});
      return cached;
    }

    final isNvidia = _isNvidiaEndpoint(effEndpoint);
    final modelChain = <String>[
      primary,
      if (isNvidia && !isLocal)
        ..._modelFallbacks.where((m) => m != primary),
    ];

    Object? lastError;
    for (final model in modelChain) {
      try {
        final rotator = NvidiaApiKeyRotator(keys);
        final pageFragment = await _generatePlan(
          rotator: rotator,
          keys: keys,
          plan: plan,
          compactBase: compactBase,
          jobDescription: jd,
          sectionsToOptimize: effectiveSections,
          customInstructions: customInstructions,
          endpoint: effEndpoint,
          primaryModel: model,
          onProgress: onProgress,
        );
        final out = finalizeHtml(clean(pageFragment), baseHtml);
        _putCache(cacheKey, out);
        return out;
      } catch (e) {
        lastError = e;
        final msg = e.toString().toLowerCase();
        if (msg.contains('429') ||
            msg.contains('413') ||
            msg.contains('404') ||
            msg.contains('not found') ||
            msg.contains('rate') ||
            msg.contains('resource') ||
            msg.contains('exhausted') ||
            msg.contains('quota') ||
            msg.contains('too large') ||
            msg.contains('all api keys exhausted')) {
          // Try next model only if more remain; else surface friendly error.
          if (model == modelChain.last) {
            throw Exception(
                'Provider quota/model unavailable. Try another model, add an API key, or use Ollama.');
          }
          developer.log('Model $model unavailable; trying next',
              name: 'ResumeForge.NvidiaService', error: e);
          continue;
        }
        if (!isNvidia || isLocal || model == modelChain.last) rethrow;
        developer.log('Model $model failed; trying next',
            name: 'ResumeForge.NvidiaService', error: e);
      }
    }
    throw lastError is Exception
        ? lastError as Exception
        : Exception(lastError?.toString() ?? 'All models failed.');
  }

  /// Step 1: screen dump → keywords / responsibilities / key points brief.
  static Future<String> _resolveJobBrief({
    required String screenDump,
    required List<String> keys,
    required String endpoint,
    required String tailorModel,
    void Function(String stage)? onProgress,
    bool forceCompress = false,
  }) async {
    final briefKey = Object.hash(_cacheVersion, 'brief', screenDump);
    final hit = _briefCache[briefKey];
    if (hit != null) {
      developer.log('JD brief cache hit',
          name: 'ResumeForge.NvidiaService',
          error: {'briefChars': hit.length});
      onProgress?.call('Using cached formatted job description');
      return hit;
    }

    if (!forceCompress && JdCompressor.shouldSkipCompress(screenDump)) {
      onProgress?.call('Job description already compact');
      final brief = trimJd(screenDump);
      _putBriefCache(briefKey, brief);
      return brief;
    }

    onProgress?.call('Formatting job description (step 1 of 2)');
    final compressModelId = compressModel;
    final rotator = NvidiaApiKeyRotator(keys);
    final brief = await _compressScreenDump(
      screenDump: screenDump,
      rotator: rotator,
      endpoint: endpoint,
      model: compressModelId,
    );
    _putBriefCache(briefKey, brief);
    return brief;
  }

  /// Step 1: screen dump → keywords / responsibilities / key points brief.
  static Future<String> _compressScreenDump({
    required String screenDump,
    required NvidiaApiKeyRotator rotator,
    required String endpoint,
    required String model,
  }) async {
    final prompt = JdCompressor.buildCompressPrompt(screenDump);
    try {
      final raw = await rotator.runWithRotation(
        (key) => _complete(
          key,
          prompt,
          endpoint: endpoint,
          model: model,
          systemContent: JdCompressor.systemPrompt,
          maxTokensOverride: JdCompressor.maxCompressTokens,
        ),
      );
      final brief = JdCompressor.briefOrFallback(clean(raw), screenDump);
      developer.log('JD compressed',
          name: 'ResumeForge.NvidiaService',
          error: {
            'dumpChars': screenDump.length,
            'briefChars': brief.length,
            'estTokens': ResumeChunker.estimateTokens(brief),
            'model': model,
          });
      return brief;
    } catch (e) {
      developer.log('JD compress failed; using trimmed dump',
          name: 'ResumeForge.NvidiaService', error: e);
      return trimJd(screenDump);
    }
  }

  /// Partial-section stream (Skills/Experience). Full page only if no section jobs.
  static Future<String> _generatePlan({
    required NvidiaApiKeyRotator rotator,
    required List<String> keys,
    required ResumeChunkPlan plan,
    required String compactBase,
    required String jobDescription,
    required List<String> sectionsToOptimize,
    required String customInstructions,
    required String endpoint,
    required String primaryModel,
    void Function(String stage)? onProgress,
  }) async {
    if (plan.useFullPrompt || plan.sectionJobs.isEmpty) {
      onProgress?.call('Tailoring resume (full page fallback)');
      final full = plan.fullPrompt ??
          buildResumePrompt(
            compactBase,
            jobDescription,
            sectionsToOptimize,
            customInstructions,
          );
      developer.log('tailor full-prompt stream',
          name: 'ResumeForge.NvidiaService',
          error: {
            'estTokens': ResumeChunker.estimateTokens(full),
            'model': primaryModel,
          });
      return rotator.runWithRotation(
        (key) => _complete(
          key,
          full,
          endpoint: endpoint,
          model: primaryModel,
          systemContent: _pageSystem,
        ),
      );
    }

    final headings = plan.sectionJobs.map((j) => j.heading).toList();
    developer.log('tailor partial sections sequential',
        name: 'ResumeForge.NvidiaService',
        error: {
          'sections': headings,
          'model': primaryModel,
          'concurrency': sectionConcurrency,
        });

    final split = ResumeChunker.splitPageSections(compactBase);
    onProgress?.call('Tailoring resume (step 2 of 2)');
    final rewritten = await _runSectionJobsSequential(
      keys: keys,
      jobs: plan.sectionJobs,
      endpoint: endpoint,
      model: primaryModel,
      onProgress: onProgress,
    );
    final sectionHtmls = <String>[];
    for (final s in split.sections) {
      var html = s.html;
      if (ResumeChunker.sectionMatchesFilter(s.heading, const ['Skills'])) {
        final skills =
            rewritten[ResumeSectionChunkJob.mergeIdSkills];
        if (skills != null) html = skills;
      }
      if (ResumeChunker.sectionMatchesFilter(s.heading, const ['Experience'])) {
        final firstEntry =
            rewritten[ResumeSectionChunkJob.mergeIdExperienceFirst];
        if (firstEntry != null) {
          html = ResumeChunker.mergeFirstExperienceEntry(html, firstEntry);
        }
      }
      sectionHtmls.add(html);
    }
    return ResumeChunker.mergeSections(split.headerHtml, sectionHtmls);
  }

  /// One section at a time after JD compress. Failed section keeps original HTML.
  static Future<Map<String, String>> _runSectionJobsSequential({
    required List<String> keys,
    required List<ResumeSectionChunkJob> jobs,
    required String endpoint,
    required String model,
    void Function(String stage)? onProgress,
  }) async {
    final rewritten = <String, String>{};
    var failures = 0;
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      onProgress?.call('Tailoring ${job.heading} (${i + 1}/${jobs.length})');
      final rotator = NvidiaApiKeyRotator(
        keys,
        startingIndex: i % keys.length,
      );
      try {
        final raw = await rotator.runWithRotation(
          (key) => _complete(
            key,
            job.prompt,
            endpoint: endpoint,
            model: model,
            systemContent:
                job.isFirstExperienceEntry ? _entrySystem : _sectionSystem,
          ),
        );
        rewritten[job.mergeId] = job.isFirstExperienceEntry
            ? normalizeExperienceEntryHtml(clean(raw))
            : normalizeSectionHtml(clean(raw), job.heading);
      } catch (e) {
        failures++;
        developer.log(
          'Section "${job.heading}" failed; keeping original',
          name: 'ResumeForge.NvidiaService',
          error: e,
        );
      }
    }
    if (rewritten.isEmpty && jobs.isNotEmpty) {
      throw Exception(
        'All section tailor requests failed (model unavailable or quota). '
        'Try another model or API key.',
      );
    }
    if (failures > 0) {
      developer.log(
        'Partial section tailor: $failures failed, ${rewritten.length} ok',
        name: 'ResumeForge.NvidiaService',
      );
    }
    return rewritten;
  }

  /// Kept for tests / callers that batch; prefers sequential via [sectionConcurrency]=1.
  static Future<Map<String, String>> _runSectionJobsParallel({
    required List<String> keys,
    required List<ResumeSectionChunkJob> jobs,
    required String endpoint,
    required String model,
  }) =>
      _runSectionJobsSequential(
        keys: keys,
        jobs: jobs,
        endpoint: endpoint,
        model: model,
      );

  static Future<String> _complete(
    String apiKey,
    String prompt, {
    String? endpoint,
    String? model,
    String systemContent = _pageSystem,
    int? maxTokensOverride,
  }) async {
    final effEndpoint = (endpoint != null && endpoint.trim().isNotEmpty)
        ? endpoint.trim()
        : NvidiaService.endpoint;
    final effModel = (model != null && model.trim().isNotEmpty)
        ? model.trim()
        : NvidiaService.defaultModel;
    final local = _isLocalEndpoint(effEndpoint);
    final nvidia = _isNvidiaEndpoint(effEndpoint);
    final tokenBudget =
        maxTokensOverride ?? (nvidia ? maxTokens : 3500);
    final content = await NvidiaStreamClient().complete(
      endpoint: effEndpoint,
      apiKey: apiKey,
      model: effModel,
      messages: [
        {'role': 'system', 'content': systemContent},
        {'role': 'user', 'content': prompt},
      ],
      maxTokens: tokenBudget,
      temperature: 0.15,
      topP: 0.9,
      chatTemplateKwargs: nvidia ? {'enable_thinking': false} : null,
      timeout: local ? const Duration(seconds: 120) : perRequestTimeout,
    );
    developer.log('LLM streamed response',
        name: 'ResumeForge.NvidiaService',
        error: {'responseLength': content.length, 'model': effModel});
    if (content.trim().isEmpty) {
      throw Exception('API returned no completion.');
    }
    return content;
  }

  /// Pull the matching `<h2>` section from a model reply (page or bare fragment).
  @visibleForTesting
  static String normalizeExperienceEntryHtml(String raw) {
    final cleaned = clean(raw).trim();
    if (cleaned.isEmpty) {
      throw Exception('Model returned empty HTML for experience entry.');
    }
    var body = cleaned;
    if (!RegExp(r'<div\s+class="entry"', caseSensitive: false).hasMatch(body)) {
      body = '<div class="entry">$body</div>';
    }
    final split = ResumeChunker.splitFirstExperienceEntry(
      '<h2>Experience</h2>$body',
    );
    if (split != null && split.firstEntryHtml.trim().isNotEmpty) {
      return split.firstEntryHtml;
    }
    throw Exception('Model returned incomplete experience entry HTML.');
  }

  @visibleForTesting
  static String normalizeSectionHtml(String raw, String heading) {
    final cleaned = clean(raw).trim();
    if (cleaned.isEmpty) {
      throw Exception('Model returned empty HTML for section "$heading".');
    }
    final wrapped = cleaned.contains('class="page"') || cleaned.contains('<h2')
        ? (cleaned.contains('class="page"')
            ? cleaned
            : '<div class="page">$cleaned</div>')
        : null;
    if (wrapped != null) {
      final split = ResumeChunker.splitPageSections(wrapped);
      for (final s in split.sections) {
        if (ResumeChunker.sectionMatchesFilter(s.heading, [heading])) {
          return s.html;
        }
      }
      if (split.sections.length == 1) return split.sections.first.html;
    }
    if (RegExp(r'^<h2\b', caseSensitive: false).hasMatch(cleaned)) {
      return cleaned;
    }
    throw Exception(
        'Model returned incomplete section HTML for "$heading".');
  }

  // --- helpers (public for tests) ---

  static String trimJd(String jd) {
    var t = jd.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length > maxJdChars) {
      t = '${t.substring(0, maxJdChars)}… [truncated ${jd.length - maxJdChars} chars for speed]';
    }
    return t;
  }

  static String extractStyleBlock(String html) {
    final m = RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false)
        .firstMatch(html);
    return m?.group(0) ?? '';
  }

  static String compactHtml(String html) {
    // Drop CSS — ATS body text is what matters; style alone is ~2-3k tokens.
    var c = html.replaceAll(
        RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
    // Collapse inter-tag whitespace; safe for this ATS template (no <pre>).
    c = c.replaceAll(RegExp(r'>\s+<'), '><');
    c = c.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    return c.trim();
  }

  /// Merge model page-fragment into the original base document (keeps CSS/layout).
  static String finalizeHtml(String modelOut, String baseHtml) {
    final page = extractPageFragment(modelOut);
    if (page == null || !isCompleteResumeHtml(page)) {
      throw Exception(
          'Model returned incomplete resume HTML (truncated or missing body). '
          'Deselect some sections and retry.');
    }
    return replacePage(baseHtml, page);
  }

  static String? extractPageFragment(String raw) {
    final cleaned = clean(raw);
    final pageMatch = RegExp(
      r'<div\s+class="page"[^>]*>[\s\S]*</div\s*>',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (pageMatch != null) return pageMatch.group(0);

    // Full document fallback — pull body inner HTML.
    final bodyMatch = RegExp(
      r'<body[^>]*>([\s\S]*)</body>',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (bodyMatch != null) {
      final inner = bodyMatch.group(1)!.trim();
      if (inner.contains('class="page"')) return inner;
      return '<div class="page">$inner</div>';
    }

    // Bare fragment with resume sections.
    if (cleaned.contains('Summary') || cleaned.contains('Experience')) {
      return cleaned.contains('class="page"')
          ? cleaned
          : '<div class="page">$cleaned</div>';
    }
    return null;
  }

  static String replacePage(String baseHtml, String pageDiv) {
    final replaced = baseHtml.replaceFirst(
      RegExp(r'<div\s+class="page"[^>]*>[\s\S]*</div>\s*</body>',
          caseSensitive: false),
      '$pageDiv</body>',
    );
    if (replaced != baseHtml) return replaced;
    // Fallback: replace entire body.
    return baseHtml.replaceFirstMapped(
      RegExp(r'(<body[^>]*>)[\s\S]*(</body>)', caseSensitive: false),
      (m) => '${m[1]}$pageDiv${m[2]}',
    );
  }

  static bool isCompleteResumeHtml(String html) {
    final lower = html.toLowerCase();
    if (html.trim().length < 800) return false;
    final styleOnly =
        RegExp(r'^\s*<style[\s\S]*</style>\s*$', caseSensitive: false)
            .hasMatch(html);
    if (styleOnly) return false;
    final hasPage = lower.contains('class="page"') || lower.contains('<body');
    final hasSection = lower.contains('summary') &&
        (lower.contains('experience') || lower.contains('skills'));
    return hasPage && hasSection;
  }

  /// Kept for tests / callers that only need CSS reinjection.
  static String restoreStyle(String html, String styleBlock) {
    if (styleBlock.isEmpty) return html;
    final trimmed = html.trim();
    if (trimmed.isEmpty) return trimmed;
    if (RegExp(r'<style[^>]*>', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed.replaceFirst(
        RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
        styleBlock,
      );
    }
    if (RegExp(r'</head>', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed.replaceFirst(
        RegExp(r'</head>', caseSensitive: false),
        '$styleBlock</head>',
      );
    }
    return '<!DOCTYPE html><html><head>$styleBlock</head><body>$trimmed</body></html>';
  }

  static String clean(String raw) {
    return raw
        .replaceAll(RegExp(r'```html\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();
  }

  static bool _isLocalEndpoint(String endpoint) {
    final e = endpoint.toLowerCase();
    return e.contains('localhost') ||
        e.contains('127.0.0.1') ||
        e.contains('10.0.2.2');
  }

  static bool _isNvidiaEndpoint(String endpoint) {
    final e = endpoint.toLowerCase();
    return e.contains('integrate.api.nvidia.com') || e.contains('api.nvidia.com');
  }

  static int _cacheKey({
    required String jd,
    required String model,
    required String endpoint,
    required List<String> sections,
    required String custom,
  }) {
    return Object.hash(_cacheVersion, jd, model, endpoint, sections.join(','), custom);
  }

  static void _putCache(int key, String html) {
    if (_cache.length >= _cacheMaxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = html;
  }

  static void _putBriefCache(int key, String brief) {
    if (_briefCache.length >= _briefCacheMaxEntries) {
      _briefCache.remove(_briefCache.keys.first);
    }
    _briefCache[key] = brief;
  }

  @visibleForTesting
  static void clearCacheForTests() {
    _cache.clear();
    _briefCache.clear();
  }
}
