import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:resumetailor/services/nvidia_service.dart';

/// Builds an SSE-style chunked body from a list of content deltas, terminated
/// by `data: [DONE]`.
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

/// A fake [http.Client] that returns a canned streamed response for `send`.
class _FakeStreamingClient extends http.BaseClient {
  _FakeStreamingClient(this.body, {this.statusCode = 200});

  final String body;
  final int statusCode;
  int sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount++;
    final bytes = utf8.encode(body);
    // Emit the body in several small chunks to mimic a real streamed response.
    final controller = StreamController<List<int>>();
    scheduleMicrotask(() async {
      const chunk = 24;
      for (var i = 0; i < bytes.length; i += chunk) {
        controller.add(bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk));
        await Future<void>.delayed(Duration.zero);
      }
      await controller.close();
    });
    return http.StreamedResponse(controller.stream, statusCode);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('streaming: onDelta called multiple times and Future returns assembled HTML', () async {
    final deltas = [
      '<!DOCTYPE html><html>',
      '<body><h2>Summary</h2>',
      '<p>Tailored content</p>',
      '</body></html>',
    ];
    final client = _FakeStreamingClient(_sseBody(deltas));

    final partials = <String>[];
    final result = await NvidiaService.tailorResume(
      'some JD',
      apiKey: 'test-key',
      baseHtmlOverride: '<!DOCTYPE html><html></html>',
      httpClient: client,
      onDelta: (partial) => partials.add(partial),
    );

    // onDelta fired for each content-bearing chunk.
    expect(partials.length, equals(deltas.length));
    // Content grows monotonically.
    for (var i = 1; i < partials.length; i++) {
      expect(partials[i].length, greaterThanOrEqualTo(partials[i - 1].length));
    }
    // Final result equals the concatenated, fence-stripped HTML.
    expect(result, equals(deltas.join()));
    // The last onDelta value equals the final result.
    expect(partials.last, equals(result));
  });

  test('streaming: markdown fences are stripped from accumulated output', () async {
    final deltas = ['```html\n', '<!DOCTYPE html><html></html>', '\n```'];
    final client = _FakeStreamingClient(_sseBody(deltas));

    final result = await NvidiaService.tailorResume(
      'some JD',
      apiKey: 'test-key',
      baseHtmlOverride: '<!DOCTYPE html><html></html>',
      httpClient: client,
    );

    expect(result, equals('<!DOCTYPE html><html></html>'));
  });

  test('streaming: falls back to delta.content over message.content and stops on [DONE]', () async {
    // Include a trailing frame after [DONE] that must be ignored.
    final body =
        'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': 'HELLO'},
                },
              ],
            })}\n\n'
        'data: [DONE]\n\n'
        'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': 'IGNORED'},
                },
              ],
            })}\n\n';
    final client = _FakeStreamingClient(body);

    final result = await NvidiaService.tailorResume(
      'some JD',
      apiKey: 'test-key',
      baseHtmlOverride: '<!DOCTYPE html><html></html>',
      httpClient: client,
    );

    expect(result, equals('HELLO'));
  });

  test('streaming: non-2xx before content triggers model rotation', () async {
    final client = _FakeStreamingClient('{"error":"bad"}', statusCode: 500);

    await expectLater(
      NvidiaService.tailorResume(
        'some JD',
        apiKey: 'test-key',
        baseHtmlOverride: '<!DOCTYPE html><html></html>',
        httpClient: client,
      ),
      throwsA(isA<Exception>()),
    );
    // Rotation was attempted (limited to 2 tries in the service).
    expect(client.sendCount, greaterThanOrEqualTo(2));
  });

  test('generateOverride path still works and invokes onDelta once', () async {
    final partials = <String>[];
    final result = await NvidiaService.tailorResume(
      'some JD',
      apiKey: 'test-key',
      baseHtmlOverride: '<!DOCTYPE html><html></html>',
      onDelta: (partial) => partials.add(partial),
      generateOverride: (prompt) async =>
          '```html\n<!DOCTYPE html><html><body>OK</body></html>\n```',
    );

    expect(result, equals('<!DOCTYPE html><html><body>OK</body></html>'));
    expect(partials, equals([result]));
  });
}
