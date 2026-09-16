import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:test/test.dart';

void main() {
  group('AndroidAdbDeviceAdapter', () {
    test(
        'maps device listing and bounds process output at its concrete boundary',
        () async {
      final runner = _QueueRunner([
        const ProcessResultData(
          exitCode: 0,
          stdout: 'List of devices attached\nphysical-1 device model:Pixel\n',
          stderr: '',
        ),
      ]);
      final adapter = AndroidAdbDeviceAdapter(
        process: AdbProcess(runner: runner),
      );

      final devices = await adapter.listDevices();

      expect(devices, hasLength(1));
      expect(devices.single.serial, 'physical-1');
      expect(devices.single.state, 'device');
      expect(runner.calls.single.arguments, ['devices', '-l']);
    });

    test('uses a quoted remote stat command and never exposes a PDF read API',
        () async {
      final runner = _QueueRunner([
        const ProcessResultData(exitCode: 0, stdout: '321\n', stderr: ''),
      ]);
      final adapter = AndroidAdbDeviceAdapter(
        process: AdbProcess(runner: runner),
      );

      final result = await adapter.stat('physical-1', "/sdcard/resume's.pdf");

      expect(result.exists, isTrue);
      expect(result.bytes, 321);
      expect(
        runner.calls.single.arguments.last,
        contains("'/sdcard/resume'\"'\"'s.pdf'"),
      );
    });
  });
}

class _QueueRunner implements ProcessRunner {
  _QueueRunner(this._results);

  final List<ProcessResultData> _results;
  final calls = <_Call>[];

  @override
  Future<ProcessResultData> run(
      String executable, List<String> arguments) async {
    calls.add(_Call(executable, List.unmodifiable(arguments)));
    if (_results.isEmpty) throw StateError('Unexpected process invocation');
    return _results.removeAt(0);
  }
}

class _Call {
  const _Call(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
