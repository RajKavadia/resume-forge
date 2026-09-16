import 'package:physical_device_e2e/physical_device_e2e.dart';

Future<void> main() async {
  await AdbProcess(runner: _FakeRunner()).run(<String>['devices']);
  final policy = HarnessOutputPolicy(<String>['tool/physical_device_e2e/out']);
  assert(!policy.allows('lib/main.dart'));
}

class _FakeRunner implements ProcessRunner {
  @override
  Future<ProcessResultData> run(
    String executable,
    List<String> arguments,
  ) async =>
      const ProcessResultData(exitCode: 0, stdout: 'ok\r\n', stderr: '');
}
