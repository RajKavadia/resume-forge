import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'ai_provider.dart';
import 'base_resume_service.dart';
import 'gemini_service.dart' show buildResumePrompt;
import 'resume_section_service.dart';

class NvidiaService {
  /// Default provider backing this service. NVIDIA remains the default; the
  /// transport specifics (endpoint + auth header) are resolved from this
  /// [AiProvider] so a different OpenAI-compatible provider can be swapped in
  /// with minimal change.
  static const AiProvider defaultProviderDescriptor = AiProviders.nvidia;

  static const endpoint = 'https://integrate.api.nvidia.com/v1/chat/completions';
  static const defaultModel = 'nvidia/nemotron-3-ultra-550b-a55b';

  /// Tailors the resume for [jobDescription].
  ///
  /// Returns the full, fence-stripped HTML as a [Future<String>] (backward
  /// compatible). Callers that want to render text progressively can pass
  /// [onDelta]; it is invoked with the running (partial) HTML as chunks arrive
  /// from the streamed (SSE) response. When [generateOverride] is provided the
  /// non-streaming override path is used (tests depend on this) and [onDelta]
  /// is invoked once with the final content.
  ///
  /// [httpClient] is an injection seam used by tests to feed a canned SSE body;
  /// production callers leave it null and a default client is created.
  static Future<String> tailorResume(String jobDescription, {
    required String apiKey,
    String? endpointOverride,
    String? modelOverride,
    List<String> sectionsToOptimize = const [],
    String customInstructions = '',
    String? baseHtmlOverride,
    Future<String> Function(String prompt)? generateOverride,
    void Function(String partialHtml)? onDelta,
    http.Client? httpClient,
  }) async {
    if (apiKey.trim().isEmpty) throw Exception('API key is required.');
    // Base-HTML source priority: explicit override (tests) > local cache >
    // bundled asset (cached on first load).
    final baseHtml = baseHtmlOverride ?? await BaseResumeService.load();

    // Reduced-payload path: when specific sections are requested we send only
    // those section fragments to the model and merge its tailored output back
    // into the full base HTML on-device. The full-optimize path (empty
    // sectionsToOptimize) keeps embedding/returning the whole document.
    final isReduced = sectionsToOptimize.isNotEmpty;
    final allowedHeadings = isReduced
        ? ResumeSectionService.headingsForLabels(sectionsToOptimize)
        : const <String>[];

    /// Turns whatever the model returned into a complete, fence-stripped HTML
    /// document: for the reduced path this merges the tailored fragments back
    /// into [baseHtml]; for the full path it is already a whole document.
    String finalize(String rawContent) {
      final stripped = _stripFences(rawContent);
      if (!isReduced) return stripped;
      return ResumeSectionService.mergeSections(
        baseHtml,
        stripped,
        allowedHeadings: allowedHeadings,
      );
    }

    final prompt = buildResumePrompt(baseHtml, jobDescription, sectionsToOptimize, customInstructions);
    if (generateOverride != null) {
      final raw2 = await generateOverride(prompt);
      developer.log('NVIDIA returned response', name: 'ResumeForge.NvidiaService', error: {'responseLength': raw2.length});
      final merged = finalize(raw2);
      if (onDelta != null) onDelta(merged);
      return merged;
    }
    // Auto-rotation across curated fallback models on failure (fastest first)
    const fallbacks = ['nvidia/nemotron-3-ultra-550b-a55b','nvidia/nemotron-3-nano-omni-30b-a3b-reasoning','mistralai/mistral-large-2-instruct','nvidia/nemotron-3-super-120b-a12b'];
    final tried = <String>{};
    final primary = (modelOverride?.trim().isNotEmpty == true) ? modelOverride!.trim() : defaultModel;
    final queue = [primary, ...fallbacks.where((m) => m != primary)];
    Exception? lastError;
    // During streaming, show progressive content. For the reduced path the
    // model streams only fragments, so we merge each partial buffer into the
    // full base HTML before surfacing it, keeping the preview a valid document.
    void Function(String partialHtml)? streamDelta;
    if (onDelta != null) {
      streamDelta = isReduced
          ? (partial) => onDelta(ResumeSectionService.mergeSections(
                baseHtml,
                partial,
                allowedHeadings: allowedHeadings,
              ))
          : onDelta;
    }
    for (final m in queue) {
      if (tried.contains(m)) continue;
      tried.add(m);
      try {
        final raw = await _completeStreaming(
          apiKey.trim(),
          prompt,
          endpoint: endpointOverride,
          model: m,
          onDelta: streamDelta,
          httpClient: httpClient,
        );
        if (m != primary) developer.log('Model rotated to $m', name: 'ResumeForge.NvidiaService');
        developer.log('NVIDIA returned response', name: 'ResumeForge.NvidiaService', error: {'responseLength': raw.length, 'model': m});
        final merged = finalize(raw);
        // For the reduced path the streamed onDelta values were merged from
        // partial fragments; emit one final onDelta carrying the fully-merged
        // document so the last value always equals the returned result. For the
        // full path the stream already emitted the final document, so we do not
        // emit a duplicate.
        if (isReduced && onDelta != null) onDelta(merged);
        return merged;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        developer.log('Model $m failed, rotating', name: 'ResumeForge.NvidiaService', error: e);
        if (tried.length >= 2) break; // limit rotations to avoid long wait; fastest models first
        continue;
      }
    }
    throw lastError ?? Exception('All models failed');
  }

  static String _stripFences(String raw) => raw
      .replaceAll(RegExp(r'```html\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'```\s*'), '')
      .trim();

  /// Sends a streaming (`stream: true`) chat-completion request and consumes
  /// the Server-Sent-Events style body: `data: {json}` lines terminated by
  /// `data: [DONE]`. Each `choices[0].delta.content` fragment (falling back to
  /// `choices[0].message.content` for providers that return a full message) is
  /// accumulated into a buffer; [onDelta] is invoked with the running buffer as
  /// chunks arrive. Returns the full accumulated (un-stripped) content.
  ///
  /// A rotation-eligible error is thrown when the request fails BEFORE any
  /// content has streamed (non-2xx status or connection error). Once content
  /// has begun arriving the partial data is retained and no error is thrown.
  static Future<String> _completeStreaming(
    String apiKey,
    String prompt, {
    String? endpoint,
    String? model,
    void Function(String partialHtml)? onDelta,
    http.Client? httpClient,
  }) async {
    // Transport specifics (endpoint + auth header) come from the resolved
    // provider descriptor (NVIDIA by default). An explicit endpoint/model
    // override still wins; when absent we fall back to the default provider.
    final provider = defaultProviderDescriptor;
    final effEndpoint = (endpoint != null && endpoint.trim().isNotEmpty) ? endpoint.trim() : provider.endpoint;
    final effModel = (model != null && model.trim().isNotEmpty) ? model.trim() : provider.defaultModel;

    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    final buffer = StringBuffer();
    var receivedContent = false;
    try {
      final request = http.Request('POST', Uri.parse(effEndpoint));
      request.headers.addAll({
        'Authorization': provider.authHeader(apiKey),
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      });
      request.body = jsonEncode({
        'model': effModel,
        'temperature': 0.15,
        'top_p': 0.9,
        'max_tokens': 5000,
        'stream': true,
        'chat_template_kwargs': {'enable_thinking': false},
        'messages': [
          {'role': 'system', 'content': 'Return only complete raw HTML. Do not include markdown fences or commentary.'},
          {'role': 'user', 'content': prompt},
        ],
      });

      final streamed = await client.send(request).timeout(const Duration(seconds: 120));
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final body = await streamed.stream.bytesToString();
        throw Exception('NVIDIA API error (${streamed.statusCode}): $body');
      }

      // Decode the chunked body into lines and parse SSE `data:` frames.
      final lines = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final rawLine in lines.timeout(const Duration(seconds: 120))) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') break;
        Map<String, dynamic> json;
        try {
          json = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          // Ignore malformed keep-alive / partial frames.
          continue;
        }
        final choices = json['choices'] as List<dynamic>? ?? const [];
        if (choices.isEmpty) continue;
        final choice = choices.first as Map<String, dynamic>;
        final delta = choice['delta'];
        String? fragment;
        if (delta is Map && delta['content'] != null) {
          fragment = delta['content'].toString();
        } else {
          final message = choice['message'];
          if (message is Map && message['content'] != null) {
            fragment = message['content'].toString();
          }
        }
        if (fragment == null || fragment.isEmpty) continue;
        buffer.write(fragment);
        receivedContent = true;
        if (onDelta != null) onDelta(_stripFences(buffer.toString()));
      }

      if (!receivedContent) {
        throw Exception('NVIDIA API returned no completion.');
      }
      return buffer.toString();
    } catch (e) {
      // If content already started streaming, retain it rather than rotating.
      if (receivedContent) {
        developer.log('Stream interrupted after partial content; retaining', name: 'ResumeForge.NvidiaService', error: e);
        return buffer.toString();
      }
      rethrow;
    } finally {
      if (ownsClient) client.close();
    }
  }
}
