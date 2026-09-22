import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/services/nvidia_api_key_rotator.dart';

void main() {
  group('parseKeys', () {
    test('splits on commas, newlines, and semicolons', () {
      expect(
        parseKeys('nvapi-test-1, nvapi-test-2\nnvapi-test-3;nvapi-test-4'),
        equals([
          'nvapi-test-1',
          'nvapi-test-2',
          'nvapi-test-3',
          'nvapi-test-4',
        ]),
      );
    });

    test('trims, drops empties, dedupes preserving order', () {
      expect(
        parseKeys('  nvapi-test-1 ,\n, nvapi-test-2;nvapi-test-1\n  '),
        equals(['nvapi-test-1', 'nvapi-test-2']),
      );
    });

    test('empty raw yields empty list', () {
      expect(parseKeys(''), isEmpty);
      expect(parseKeys('  ,\n;  '), isEmpty);
    });
  });

  group('NvidiaApiKeyRotator', () {
    test('rotation order follows starting index then advance', () {
      final rotator = NvidiaApiKeyRotator(
        ['nvapi-test-1', 'nvapi-test-2', 'nvapi-test-3'],
        startingIndex: 1,
      );
      expect(rotator.currentKey, 'nvapi-test-2');
      rotator.advance();
      expect(rotator.currentKey, 'nvapi-test-3');
      rotator.advance();
      expect(rotator.currentKey, 'nvapi-test-1');
    });

    test('advance skips markFailed keys', () {
      final rotator = NvidiaApiKeyRotator(
        ['nvapi-test-1', 'nvapi-test-2', 'nvapi-test-3'],
      );
      rotator.markFailed('nvapi-test-2');
      rotator.advance();
      expect(rotator.currentKey, 'nvapi-test-3');
      rotator.advance();
      expect(rotator.currentKey, 'nvapi-test-1');
      rotator.advance();
      expect(rotator.currentKey, 'nvapi-test-3');
    });

    test('runWithRotation tries keys in order on rate-limit errors', () async {
      final rotator = NvidiaApiKeyRotator(
        ['nvapi-test-1', 'nvapi-test-2', 'nvapi-test-3'],
      );
      final seen = <String>[];

      final result = await rotator.runWithRotation((key) async {
        seen.add(key);
        if (key != 'nvapi-test-3') {
          throw Exception('HTTP 429 rate limit');
        }
        return 'ok';
      });

      expect(result, 'ok');
      expect(seen, equals(['nvapi-test-1', 'nvapi-test-2', 'nvapi-test-3']));
    });

    test('runWithRotation skips already-failed keys', () async {
      final rotator = NvidiaApiKeyRotator(
        ['nvapi-test-1', 'nvapi-test-2', 'nvapi-test-3'],
      );
      rotator.markFailed('nvapi-test-1');
      final seen = <String>[];

      final result = await rotator.runWithRotation((key) async {
        seen.add(key);
        if (key == 'nvapi-test-2') {
          throw Exception('401 unauthorized');
        }
        return 'ok';
      });

      expect(result, 'ok');
      expect(seen, equals(['nvapi-test-2', 'nvapi-test-3']));
    });

    test('runWithRotation exhausts all keys and rethrows last error', () async {
      final rotator = NvidiaApiKeyRotator(
        ['nvapi-test-1', 'nvapi-test-2'],
      );

      await expectLater(
        () => rotator.runWithRotation((key) async {
          throw Exception('429 quota exhausted for $key');
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('nvapi-test-2'),
          ),
        ),
      );
    });

    test('single key is passthrough (one attempt)', () async {
      final rotator = NvidiaApiKeyRotator(['nvapi-test-only']);
      var calls = 0;

      await expectLater(
        () => rotator.runWithRotation((key) async {
          calls++;
          expect(key, 'nvapi-test-only');
          throw Exception('429 rate limit');
        }),
        throwsA(isA<Exception>()),
      );
      expect(calls, 1);
    });

    test('non-rotatable errors are not retried', () async {
      final rotator = NvidiaApiKeyRotator(
        ['nvapi-test-1', 'nvapi-test-2'],
      );
      var calls = 0;

      await expectLater(
        () => rotator.runWithRotation((key) async {
          calls++;
          throw Exception('network timeout');
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('network timeout'),
          ),
        ),
      );
      expect(calls, 1);
    });
  });
}
