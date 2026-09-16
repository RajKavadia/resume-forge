import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:resumetailor/services/ai_provider.dart';
import 'package:resumetailor/services/nvidia_service.dart';

/// Builds an SSE-style body from content deltas, terminated by `data: [DONE]`.
String _sseBody(List<String> deltas) {
  final b = StringBuffer();
  for (final d in deltas) {
    b.write('data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': d},
            },
          ],
        })}\n\n');
  }
  b.write('data: [DONE]\n\n');
  return b.toString();
}

/// A fake client that records every request it sends and replays a canned SSE
/// body. Optionally records the model of each request so rotation can be
/// asserted.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.body, {this.statusCode = 200});

  final String body;
  final int statusCode;
  final List<Uri> urls = [];
  final List<String?> authHeaders = [];
  final List<String> models = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    urls.add(request.url);
    authHeaders.add(request.headers['Authorization']);
    if (request is http.Request) {
      final decoded = jsonDecode(request.body) as Map<String, dynamic>;
      models.add(decoded['model'] as String);
    }
    final bytes = utf8.encode(body);
    final controller = StreamController<List<int>>();
    scheduleMicrotask(() async {
      const chunk = 24;
      for (var i = 0; i < bytes.length; i += chunk) {
        controller.add(bytes.sublist(
            i, i + chunk > bytes.length ? bytes.length : i + chunk));
        await Future<void>.delayed(Duration.zero);
      }
      await controller.close();
    });
    return http.StreamedResponse(controller.stream, statusCode);
  }
}

/// A fake client whose stream emits some content and then errors mid-stream
/// (before any `[DONE]` sentinel), simulating a dropped connection.
class _MidStreamErrorClient extends http.BaseClient {
  int sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount++;
    final controller = StreamController<List<int>>();
    scheduleMicrotask(() async {
      // Emit a partial content frame, then error before completing.
      final frame = 'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '<h2>Summary</h2><p>Tail'},
              },
            ],
          })}\n\n';
      controller.add(utf8.encode(frame));
      await Future<void>.delayed(Duration.zero);
      controller.addError(Exception('connection reset mid-stream'));
      await controller.close();
    });
    return http.StreamedResponse(controller.stream, 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('provider selection', () {
    test('providerId "groq" routes to the Groq endpoint and Bearer auth',
        () async {
      final client = _RecordingClient(_sseBody(['<html>done</html>']));

      final result = await NvidiaService.tailorResume(
        'some JD',
        apiKey: 'groq-key',
        baseHtmlOverride: '<!DOCTYPE html><html></html>',
        httpClient: client,
        providerId: 'groq',
      );

      expect(result, equals('<html>done</html>'));
      expect(client.urls.first.toString(),
          equals(AiProviders.groq.endpoint));
      expect(client.authHeaders.first, equals('Bearer groq-key'));
      // The selected provider's default model is used, not an NVIDIA one.
      expect(client.models.first, equals(AiProviders.groq.defaultModel));
      expect(client.models.first, isNot(startsWith('nvidia/')));
    });

    test('absent providerId keeps the NVIDIA default endpoint/model',
        () async {
      final client = _RecordingClient(_sseBody(['<html>ok</html>']));

      await NvidiaService.tailorResume(
        'some JD',
        apiKey: 'nv-key',
        baseHtmlOverride: '<!DOCTYPE html><html></html>',
        httpClient: client,
      );

      expect(client.urls.first.toString(),
          equals(AiProviders.nvidia.endpoint));
      expect(client.models.first, equals(NvidiaService.defaultModel));
    });

    test('unknown providerId falls back to NVIDIA (default behavior)',
        () async {
      final client = _RecordingClient(_sseBody(['<html>ok</html>']));

      await NvidiaService.tailorResume(
        'some JD',
        apiKey: 'nv-key',
        baseHtmlOverride: '<!DOCTYPE html><html></html>',
        httpClient: client,
        providerId: 'does-not-exist',
      );

      expect(client.urls.first.toString(),
          equals(AiProviders.nvidia.endpoint));
      expect(client.models.first, equals(NvidiaService.defaultModel));
    });
  });

  group('provider-aware rotation', () {
    test('rotation for Groq only sends Groq models, never NVIDIA IDs',
        () async {
      // 500 before any content forces rotation through the provider's catalog.
      final client = _RecordingClient('{"error":"bad"}', statusCode: 500);

      await expectLater(
        NvidiaService.tailorResume(
          'some JD',
          apiKey: 'groq-key',
          baseHtmlOverride: '<!DOCTYPE html><html></html>',
          httpClient: client,
          providerId: 'groq',
        ),
        throwsA(isA<Exception>()),
      );

      expect(client.models, isNotEmpty);
      for (final m in client.models) {
        expect(m, isNot(startsWith('nvidia/')));
        expect(AiProviders.groq.fallbackModels, contains(m));
      }
    });

    test('rotation for the NVIDIA default sends NVIDIA models', () async {
      final client = _RecordingClient('{"error":"bad"}', statusCode: 500);

      await expectLater(
        NvidiaService.tailorResume(
          'some JD',
          apiKey: 'nv-key',
          baseHtmlOverride: '<!DOCTYPE html><html></html>',
          httpClient: client,
        ),
        throwsA(isA<Exception>()),
      );

      expect(client.models.first, equals(NvidiaService.defaultModel));
      for (final m in client.models) {
        expect(AiProviders.nvidia.fallbackModels, contains(m));
      }
    });
  });

  group('mid-stream interruption is a failure, not a truncated success', () {
    test('full path: mid-stream error surfaces as an exception', () async {
      final client = _MidStreamErrorClient();

      await expectLater(
        NvidiaService.tailorResume(
          'some JD',
          apiKey: 'nv-key',
          baseHtmlOverride: '<!DOCTYPE html><html></html>',
          httpClient: client,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('reduced path: truncated fragment is NOT merged/returned as success',
        () async {
      const base = '''
<!DOCTYPE html><html><head><style>x</style></head><body><div class="page">
<h2>Summary</h2><p>SUMMARY_ORIGINAL</p>
<h2>Skills</h2><p>SKILLS_ORIGINAL</p>
</div></body></html>''';
      final client = _MidStreamErrorClient();

      await expectLater(
        NvidiaService.tailorResume(
          'some JD',
          apiKey: 'nv-key',
          baseHtmlOverride: base,
          sectionsToOptimize: const ['Summary'],
          httpClient: client,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
