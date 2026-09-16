import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ProcessResultData {
  const ProcessResultData({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class ProcessRunner {
  Future<ProcessResultData> run(String executable, List<String> arguments);
}

class IoProcessRunner implements ProcessRunner {
  const IoProcessRunner();

  @override
  Future<ProcessResultData> run(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(executable, arguments);
    return ProcessResultData(
      exitCode: result.exitCode as int,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }
}

class AdbProcess {
  AdbProcess({ProcessRunner? runner, this.adbExecutable = 'adb'})
      : _runner = runner ?? const IoProcessRunner();

  final ProcessRunner _runner;
  final String adbExecutable;

  Future<ProcessResultData> run(List<String> arguments) async {
    final result = await _runner.run(adbExecutable, arguments);
    return ProcessResultData(
      exitCode: result.exitCode,
      stdout: _sanitize(result.stdout),
      stderr: _sanitize(result.stderr),
    );
  }

  Future<ProcessResultData> runForDevice(
    String serial,
    List<String> arguments,
  ) =>
      run(<String>['-s', serial, ...arguments]);

  static String _sanitize(String value) {
    // ADB command output is bounded before it can enter records or errors.
    const maxLength = 4096;
    final normalized = value.replaceAll(RegExp(r'[\r\n]+'), '\n');
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}…';
  }

  static Uint8List decodeBytes(String output) =>
      Uint8List.fromList(utf8.encode(output));
}
