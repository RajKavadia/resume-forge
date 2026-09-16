import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../adb_adapter.dart';

void main() {
  group('AdbDeviceAdapter', () {
    test('reports unauthorized and offline devices from ADB state output',
        () async {
      final adapter = AdbDeviceAdapter(
        process: _FakeAdbProcess(<_Invocation, Object>{
          const _Invocation('adb', <String>['devices', '-l']): _result(
              stdout:
                  'List of devices attached\nunauthorized\tunauthorized\noffline\toffline\n'),
        }).call,
      );

      final devices = await adapter.listDevices();

      expect(
        devices.map((device) => (device.serial, device.state)),
        equals(<(String, String)>[
          ('unauthorized', 'unauthorized'),
          ('offline', 'offline'),
        ]),
      );
    });

    test('returns no devices when device listing fails', () async {
      final adapter = AdbDeviceAdapter(
        process: _FakeAdbProcess(<_Invocation, Object>{
          const _Invocation('adb', <String>['devices', '-l']):
              _result(exitCode: 1, stderr: 'adb server unavailable'),
        }).call,
      );

      expect(await adapter.listDevices(), isEmpty);
    });

    test('preserves launch failure and bounds its stderr', () async {
      const packageName = 'com.example.resume';
      final stderr = 'launch failed: ${'x' * 5000}';
      final adapter = AdbDeviceAdapter(
        process: _FakeAdbProcess(<_Invocation, Object>{
          const _Invocation('adb', <String>[
            '-s',
            'physical-1',
            'shell',
            'monkey',
            '-p',
            packageName,
            '1',
          ]): _result(exitCode: 1, stderr: stderr),
        }).call,
      );

      final result = await adapter.launch('physical-1', packageName);

      expect(result.succeeded, isFalse);
      expect(result.command.exitCode, equals(1));
      expect(result.command.stderr, hasLength(4097));
      expect(result.command.stderr, endsWith('…'));
      expect(result.command.command, contains(packageName));
    });

    test('propagates a process timeout without treating it as success',
        () async {
      final adapter = AdbDeviceAdapter(
        process: _FakeAdbProcess(<_Invocation, Object>{
          const _Invocation('adb', <String>['devices', '-l']):
              TimeoutException('ADB command exceeded its configured timeout'),
        }).call,
      );

      await expectLater(
          adapter.listDevices(), throwsA(isA<TimeoutException>()));
    });

    test('quotes remote stat paths and escapes embedded single quotes',
        () async {
      const path = "/data/user/0/app/resume draft's copy.html";
      const quotedPath = "'/data/user/0/app/resume draft'\"'\"'s copy.html'";
      final invocation = _Invocation('adb', <String>[
        '-s',
        'physical-1',
        'shell',
        'sh',
        '-c',
        'if [ -f $quotedPath ]; then stat -c %s $quotedPath; else echo MISSING; fi',
      ]);
      final adapter = AdbDeviceAdapter(
        process: _FakeAdbProcess(<_Invocation, Object>{
          invocation: _result(stdout: '256\n'),
        }).call,
      );

      final metadata = await adapter.stat('physical-1', path);

      expect(metadata.exists, isTrue);
      expect(metadata.bytes, equals(256));
    });

    test('redacts secret text from command and stderr diagnostics', () async {
      const secret = 'nvapi-super-secret';
      const encodedSecret = 'nvapi-super-secret';
      final adapter = AdbDeviceAdapter(
        process: _FakeAdbProcess(<_Invocation, Object>{
          const _Invocation('adb', <String>[
            '-s',
            'physical-1',
            'shell',
            'input',
            'text',
            encodedSecret,
          ]): _result(exitCode: 1, stderr: 'input rejected $secret'),
        }).call,
      );

      final result = await adapter.text('physical-1', secret, secret: true);

      expect(result.succeeded, isFalse);
      expect(result.command.command, isNot(contains(secret)));
      expect(result.command.stderr, isNot(contains(secret)));
      expect(result.command.command, contains('<redacted>'));
      expect(result.command.stderr, contains('<redacted>'));
    });
  });
}

class _FakeAdbProcess {
  _FakeAdbProcess(this.responses);

  final Map<_Invocation, Object> responses;

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    final response = responses[_Invocation(executable, arguments)];
    if (response == null) {
      throw StateError(
          'Unexpected ADB invocation: $executable ${arguments.join(' ')}');
    }
    if (response is Exception) throw response;
    if (response is Error) throw response;
    return response as ProcessResult;
  }
}

class _Invocation {
  const _Invocation(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  @override
  bool operator ==(Object other) =>
      other is _Invocation &&
      executable == other.executable &&
      _sameArguments(arguments, other.arguments);

  @override
  int get hashCode => Object.hash(executable, Object.hashAll(arguments));
}

bool _sameArguments(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

ProcessResult _result(
        {int exitCode = 0, String stdout = '', String stderr = ''}) =>
    ProcessResult(0, exitCode, stdout, stderr);
