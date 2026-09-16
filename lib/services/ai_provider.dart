/// Provider-agnostic backend seam for OpenAI-compatible chat-completion APIs.
///
/// Both NVIDIA NIM and Groq speak the OpenAI chat-completions JSON schema
/// (messages[], model, temperature, top_p, max_tokens, stream,
/// choices[].message.content and for streaming choices[].delta.content), so the
/// only things that differ between backends are the endpoint URL and how the
/// Authorization header is built. This abstraction isolates those transport
/// specifics so a different provider (e.g. Groq) can be swapped in later with
/// minimal change, while NVIDIA remains the default and default behavior is
/// unchanged.
///
/// Extension point: to make a provider user-selectable, add an optional
/// providerId to the persisted config and resolve it via [AiProviders.byId].
/// The default resolution ([AiProviders.defaultProvider]) always returns NVIDIA
/// so existing persisted configs and flows keep working unchanged.
class AiProvider {
  /// Stable identifier used for registry lookup (e.g. 'nvidia', 'groq').
  final String id;

  /// Human-readable name.
  final String name;

  /// OpenAI-compatible chat-completions endpoint URL.
  final String endpoint;

  /// Default model for this provider.
  final String defaultModel;

  const AiProvider({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.defaultModel,
  });

  /// Builds the Authorization header value for the given API key.
  /// All current OpenAI-compatible providers use `Bearer <apiKey>`.
  String authHeader(String apiKey) => 'Bearer $apiKey';
}

/// Registry of known providers and default resolution.
class AiProviders {
  AiProviders._();

  /// NVIDIA NIM provider (the default backend).
  static const nvidia = AiProvider(
    id: 'nvidia',
    name: 'NVIDIA NIM',
    endpoint: 'https://integrate.api.nvidia.com/v1/chat/completions',
    defaultModel: 'nvidia/nemotron-3-ultra-550b-a55b',
  );

  /// Groq provider (OpenAI-compatible). Not active by default; provided so it
  /// can be swapped in with minimal change once a Groq key is available.
  static const groq = AiProvider(
    id: 'groq',
    name: 'Groq',
    endpoint: 'https://api.groq.com/openai/v1/chat/completions',
    defaultModel: 'llama-3.3-70b-versatile',
  );

  /// All registered providers.
  static const List<AiProvider> all = [nvidia, groq];

  /// The default provider. NVIDIA remains the default backend.
  static const AiProvider defaultProvider = nvidia;

  /// Looks up a provider by its [id]. Returns null when unknown.
  static AiProvider? byId(String? id) {
    if (id == null) return null;
    final key = id.trim().toLowerCase();
    for (final p in all) {
      if (p.id == key) return p;
    }
    return null;
  }

  /// Resolves the provider to use for the given [id], falling back to the
  /// [defaultProvider] (NVIDIA) when [id] is absent or unknown.
  static AiProvider resolve(String? id) => byId(id) ?? defaultProvider;
}
