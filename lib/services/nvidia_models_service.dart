import 'dart:convert';
import 'package:http/http.dart' as http;

class NvidiaModelsService {
  static const _endpoint = 'https://integrate.api.nvidia.com/v1/models';
  // Curated chat-capable models for resume tailoring (verified 2026-09)
  static const curated = [
    'nvidia/nemotron-3-ultra-550b-a55b',
    'nvidia/nemotron-3-super-120b-a12b',
    'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',
    'nvidia/llama-3.1-nemotron-ultra-253b-v1',
    'nvidia/llama-3.1-nemotron-70b-instruct',
    'nvidia/llama-3.1-nemotron-51b-instruct',
    'nvidia/nemotron-4-340b-instruct',
    'meta/llama-3.2-90b-vision-instruct',
    'meta/llama-3.2-11b-vision-instruct',
    'mistralai/mistral-large-2-instruct',
    'mistralai/mistral-large',
    'deepseek-ai/deepseek-v4-flash-0731',
    'moonshotai/kimi-k3',
    'openai/gpt-oss-20b',
  ];

  static Future<List<String>> fetch({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final res = await http.get(Uri.parse(_endpoint)).timeout(timeout);
      if (res.statusCode != 200) return curated;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data['data'] as List).map((e) => (e as Map)['id'] as String).toList();
      // Prefer curated order first, then rest
      final set = {...curated, ...list};
      // Filter out embed/reward/parse/vision-only not ideal for text gen but keep for rotation
      return set.where((m) => !m.contains('embed') && !m.contains('reward') && !m.contains('parse') && !m.contains('clip') && !m.contains('vila') && !m.contains('guard')).toList();
    } catch (_) {
      return curated;
    }
  }
}
