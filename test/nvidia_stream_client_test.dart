import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/nvidia_stream_client.dart';

Stream<List<int>> _bytes(String s) => Stream.value(utf8.encode(s));

void main() {
  group('contentFromSsePayload', () {
    test('reads delta.content', () {
      expect(
        contentFromSsePayload(
          jsonEncode({
            'choices': [
              {
                'delta': {'content': 'Hello'}
              }
            ]
          }),
        ),
        'Hello',
      );
    });

    test('falls back to message.content', () {
      expect(
        contentFromSsePayload(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Full'}
              }
            ]
          }),
        ),
        'Full',
      );
    });

    test('empty choices returns null', () {
      expect(contentFromSsePayload('{"choices":[]}'), isNull);
    });

    test('tool_calls / reasoning-only delta ignored', () {
      expect(
        contentFromSsePayload(
          jsonEncode({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {'name': 'x', 'arguments': '{}'}
                    }
                  ]
                }
              }
            ]
          }),
        ),
        isNull,
      );
      expect(
        contentFromSsePayload(
          jsonEncode({
            'choices': [
              {
                'delta': {'reasoning_content': 'thinking...'}
              }
            ]
          }),
        ),
        isNull,
      );
    });

    test('malformed JSON returns null', () {
      expect(contentFromSsePayload('{not json'), isNull);
    });
  });

  group('accumulateOpenAiSseContent', () {
    test('accumulates multiple delta chunks until [DONE]', () async {
      const sse = 'data: {"choices":[{"delta":{"content":"Hel"}}]}\n'
          'data: {"choices":[{"delta":{"content":"lo"}}]}\n'
          'data: {"choices":[{"delta":{"content":"!"}}]}\n'
          'data: [DONE]\n';
      final text = await accumulateOpenAiSseContent(_bytes(sse));
      expect(text, 'Hello!');
    });

    test('handles split chunks across stream events', () async {
      final stream = Stream<List<int>>.fromIterable([
        utf8.encode('data: {"choices":[{"delta":{"cont'),
        utf8.encode('ent":"A"}}]}\ndata: {"choices":[{"delta":{"content":"B"}}]}\n'),
        utf8.encode('data: [DONE]\n'),
      ]);
      final text = await accumulateOpenAiSseContent(stream);
      expect(text, 'AB');
    });

    test('ignores empty delta and role-only chunks', () async {
      const sse = 'data: {"choices":[{"delta":{"role":"assistant"}}]}\n'
          'data: {"choices":[{"delta":{}}]}\n'
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n'
          'data: [DONE]\n';
      final text = await accumulateOpenAiSseContent(_bytes(sse));
      expect(text, 'ok');
    });

    test('stops at [DONE] and ignores trailing noise', () async {
      const sse = 'data: {"choices":[{"delta":{"content":"x"}}]}\n'
          'data: [DONE]\n'
          'data: {"choices":[{"delta":{"content":"y"}}]}\n';
      final text = await accumulateOpenAiSseContent(_bytes(sse));
      expect(text, 'x');
    });

    test('skips comment / event lines', () async {
      const sse = ': keep-alive\n'
          'event: message\n'
          'data: {"choices":[{"delta":{"content":"z"}}]}\n'
          'data: [DONE]\n';
      final text = await accumulateOpenAiSseContent(_bytes(sse));
      expect(text, 'z');
    });

    test('message.content chunks accumulate', () async {
      const sse =
          'data: {"choices":[{"message":{"content":"part1"}}]}\n'
          'data: {"choices":[{"message":{"content":"part2"}}]}\n'
          'data: [DONE]\n';
      final text = await accumulateOpenAiSseContent(_bytes(sse));
      expect(text, 'part1part2');
    });
  });
}
