import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AiModelConfig {
  final String endpoint;
  final String model;
  final String apiKey;

  const AiModelConfig({
    required this.endpoint,
    required this.model,
    required this.apiKey,
  });

  static const defaultEndpoint = 'https://integrate.api.nvidia.com/v1/chat/completions';
  static const defaultModel = 'openai/gpt-oss-20b';

  factory AiModelConfig.defaults({String apiKey = ''}) => AiModelConfig(
        endpoint: defaultEndpoint,
        model: defaultModel,
        apiKey: apiKey,
      );

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'model': model,
        'apiKey': apiKey,
      };

  factory AiModelConfig.fromJson(Map<String, dynamic> json) => AiModelConfig(
        endpoint: (json['endpoint'] as String?)?.trim().isNotEmpty == true
            ? json['endpoint'] as String
            : defaultEndpoint,
        model: (json['model'] as String?)?.trim().isNotEmpty == true
            ? json['model'] as String
            : defaultModel,
        apiKey: json['apiKey'] as String? ?? '',
      );
}

class AiModelConfigService {
  static const _key = 'ai_model_config_v2';

  static Future<AiModelConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      // Migrate from old single api key storage
      final legacyKey = prefs.getString('nvidia_api_key') ?? '';
      return AiModelConfig.defaults(apiKey: legacyKey);
    }
    try {
      return AiModelConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AiModelConfig.defaults();
    }
  }

  static Future<void> save(AiModelConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
    // Keep legacy key in sync
    await prefs.setString('nvidia_api_key', config.apiKey);
  }
}
