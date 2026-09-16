import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'ai_provider.dart';
import 'gemini_service.dart' show buildResumePrompt;

class NvidiaService {
  /// Default provider backing this service. NVIDIA remains the default; the
  /// transport specifics (endpoint + auth header) are resolved from this
  /// [AiProvider] so a different OpenAI-compatible provider can be swapped in
  /// with minimal change.
  static const AiProvider defaultProviderDescriptor = AiProviders.nvidia;

  static const endpoint = 'https://integrate.api.nvidia.com/v1/chat/completions';
  static const defaultModel = 'nvidia/nemotron-3-ultra-550b-a55b';

  static Future<String> tailorResume(String jobDescription, {
    required String apiKey,
    String? endpointOverride,
    String? modelOverride,
    List<String> sectionsToOptimize = const [],
    String customInstructions = '',
    String? baseHtmlOverride,
    Future<String> Function(String prompt)? generateOverride,
  }) async {
    if (apiKey.trim().isEmpty) throw Exception('API key is required.');
    final baseHtml = baseHtmlOverride ?? await rootBundle.loadString('assets/Raj_Kavadia_Resume_ATS.html');
    final prompt = buildResumePrompt(baseHtml, jobDescription, sectionsToOptimize, customInstructions);
    if (generateOverride != null) {
      final raw2 = await generateOverride(prompt);
      developer.log('NVIDIA returned response', name: 'ResumeForge.NvidiaService', error: {'responseLength': raw2.length});
      return raw2.replaceAll(RegExp(r'```html\s*', caseSensitive: false), '').replaceAll(RegExp(r'```\s*'), '').trim();
    }
    // Auto-rotation across curated fallback models on failure (fastest first)
    const fallbacks = ['nvidia/nemotron-3-ultra-550b-a55b','nvidia/nemotron-3-nano-omni-30b-a3b-reasoning','mistralai/mistral-large-2-instruct','nvidia/nemotron-3-super-120b-a12b'];
    final tried = <String>{};
    final primary = (modelOverride?.trim().isNotEmpty == true) ? modelOverride!.trim() : defaultModel;
    final queue = [primary, ...fallbacks.where((m) => m != primary)];
    Exception? lastError;
    for (final m in queue) {
      if (tried.contains(m)) continue;
      tried.add(m);
      try {
        final raw = await _complete(apiKey.trim(), prompt, endpoint: endpointOverride, model: m);
        if (m != primary) developer.log('Model rotated to $m', name: 'ResumeForge.NvidiaService');
        developer.log('NVIDIA returned response', name: 'ResumeForge.NvidiaService', error: {'responseLength': raw.length, 'model': m});
        return raw.replaceAll(RegExp(r'```html\s*', caseSensitive: false), '').replaceAll(RegExp(r'```\s*'), '').trim();
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        developer.log('Model $m failed, rotating', name: 'ResumeForge.NvidiaService', error: e);
        if (tried.length >= 2) break; // limit rotations to avoid long wait; fastest models first
        continue;
      }
    }
    throw lastError ?? Exception('All models failed');
  }

  static Future<String> _complete(String apiKey, String prompt, {String? endpoint, String? model}) async {
    // Transport specifics (endpoint + auth header) come from the resolved
    // provider descriptor (NVIDIA by default). An explicit endpoint/model
    // override still wins; when absent we fall back to the default provider.
    final provider = defaultProviderDescriptor;
    final effEndpoint = (endpoint != null && endpoint.trim().isNotEmpty) ? endpoint.trim() : provider.endpoint;
    final effModel = (model != null && model.trim().isNotEmpty) ? model.trim() : provider.defaultModel;
    final response = await http.post(Uri.parse(effEndpoint), headers: {
      'Authorization': provider.authHeader(apiKey),
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    }, body: jsonEncode({
      'model': effModel,
      'temperature': 0.15,
      'top_p': 0.9,
      'max_tokens': 5000,
      'stream': false,
      'chat_template_kwargs': {'enable_thinking': false},
      'messages': [
        {'role': 'system', 'content': 'Return only complete raw HTML. Do not include markdown fences or commentary.'},
        {'role': 'user', 'content': prompt},
      ],
    })).timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('NVIDIA API error (${response.statusCode}): ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) throw Exception('NVIDIA API returned no completion.');
    return ((choices.first as Map)['message'] as Map)['content']?.toString() ?? '';
  }
}
