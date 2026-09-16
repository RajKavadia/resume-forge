/// Optional local API key placeholder.
///
/// Do not commit real secrets here. The app resolves the NVIDIA API key from
/// [AiModelConfigService] / user settings at runtime; this constant only exists
/// as an empty fallback for local development.
const String nvidiaApiKey = '';
