import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// OpenAI-compatible SSE streaming client for NVIDIA NIM (and similar) chat APIs.
class NvidiaStreamClient {
  /// POSTs a chat completion with `stream: true` and returns the full
  /// accumulated assistant text from SSE `data:` chunks.
  Future<String> complete({
    required String endpoint,
    required String apiKey,
    required String model,
    required List<Map<String, Object?>> messages,
    int maxTokens = 2500,
    double temperature = 0.15,
    double topP = 0.9,
    Map<String, Object?>? chatTemplateKwargs,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final client = http.Client();
    try {
      final body = <String, Object?>{
        'model': model,
        'temperature': temperature,
        'top_p': topP,
        'max_tokens': maxTokens,
        'stream': true,
        'messages': messages,
      };
      if (chatTemplateKwargs != null) {
        body['chat_template_kwargs'] = chatTemplateKwargs;
      }

      final request = http.Request('POST', Uri.parse(endpoint))
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(body);

      final streamed = await client.send(request).timeout(timeout);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final errBody = await streamed.stream.bytesToString();
        final snippet =
            errBody.length > 500 ? errBody.substring(0, 500) : errBody;
        throw Exception('API error (${streamed.statusCode}): $snippet');
      }

      return await accumulateOpenAiSseContent(streamed.stream).timeout(timeout);
    } finally {
      client.close();
    }
  }
}

/// Accumulates assistant text from an OpenAI-compatible SSE byte stream.
///
/// Handles `data: {...}` JSON lines and stops on `data: [DONE]`.
/// Exposed for unit tests (no network).
Future<String> accumulateOpenAiSseContent(Stream<List<int>> byteStream) async {
  final out = StringBuffer();
  var carry = '';
  await for (final chunk in byteStream.transform(utf8.decoder)) {
    carry += chunk;
    final parts = carry.split('\n');
    carry = parts.removeLast();
    for (final raw in parts) {
      final done = _consumeSseLine(raw, out);
      if (done) return out.toString();
    }
  }
  if (carry.isNotEmpty) {
    _consumeSseLine(carry, out);
  }
  return out.toString();
}

/// Extracts text from one SSE `data:` JSON payload, or null if none.
///
/// Prefer `choices[0].delta.content`; fall back to `choices[0].message.content`.
/// Ignores empty choices, tool_calls, and reasoning-only fields.
String? contentFromSsePayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;

    final delta = first['delta'];
    if (delta is Map) {
      final c = delta['content'];
      if (c is String && c.isNotEmpty) return c;
    }

    final message = first['message'];
    if (message is Map) {
      final c = message['content'];
      if (c is String && c.isNotEmpty) return c;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Returns true when `[DONE]` is seen (stream complete).
bool _consumeSseLine(String rawLine, StringBuffer out) {
  final line = rawLine.trimRight();
  if (line.isEmpty || line.startsWith(':')) return false;
  if (!line.startsWith('data:')) return false;
  final payload = line.substring(5).trimLeft();
  if (payload == '[DONE]') return true;
  final piece = contentFromSsePayload(payload);
  if (piece != null && piece.isNotEmpty) out.write(piece);
  return false;
}
