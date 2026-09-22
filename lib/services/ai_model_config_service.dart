import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AiModelConfig {
  final String endpoint;
  final String model;
  /// May hold multiple NVIDIA keys (comma/newline/semicolon-separated) for rotation.
  final String apiKey;

  const AiModelConfig({
    required this.endpoint,
    required this.model,
    required this.apiKey,
  });

  static const defaultEndpoint = 'https://integrate.api.nvidia.com/v1/chat/completions';
  static const defaultModel = 'openai/gpt-oss-20b';

  // --- Speed presets (open-source, local) ---
  // Desktop / web: Ollama serves OpenAI-compatible API on localhost.
  static const ollamaDesktopEndpoint =
      'http://localhost:11434/v1/chat/completions';
  // Android emulator: host loopback is 10.0.2.2. Physical device: use PC LAN IP.
  static const ollamaAndroidEndpoint =
      'http://10.0.2.2:11434/v1/chat/completions';
  static const ollamaDefaultModel = 'llama3.1:8b';
  static const ollamaApiKeyPlaceholder = 'ollama';

  // Groq — OpenAI-compatible, open models, separate free quota from NVIDIA NIM.
  static const groqEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  // Groq free-tier chat models (verified live against /v1/models).
  static const groqDefaultModel = 'openai/gpt-oss-20b';

  static bool isLocalEndpoint(String endpoint) {
    final e = endpoint.trim();
    return e.contains('localhost') ||
        e.contains('127.0.0.1') ||
        e.contains('10.0.2.2');
  }

  static bool isNvidiaEndpoint(String endpoint) {
    final e = endpoint.trim().toLowerCase();
    return e.contains('integrate.api.nvidia.com') || e.contains('api.nvidia.com');
  }

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
